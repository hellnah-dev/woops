-- =============================================================================
-- Notices from the safety team to a user (e.g. "Your photo was removed: <reason>").
-- Delivered in the app as a notification (live through Realtime, or on next
-- launch). Photo removals now require a reason, which the user sees.
-- =============================================================================

create table public.user_notices (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  title       text not null check (char_length(title) between 1 and 120),
  body        text not null check (char_length(body) between 1 and 500),
  created_at  timestamptz not null default now(),
  read_at     timestamptz
);
create index user_notices_user_idx on public.user_notices (user_id, created_at desc);

alter table public.user_notices enable row level security;
revoke all on public.user_notices from anon, authenticated;
grant select on public.user_notices to authenticated;
create policy user_notices_own on public.user_notices for select to authenticated
  using (user_id = (select auth.uid()));

alter publication supabase_realtime add table public.user_notices;

create or replace function public.get_my_notices()
returns setof public.user_notices
language sql
stable
security definer
set search_path = ''
as $$
  select * from public.user_notices
   where user_id = (select auth.uid()) and read_at is null
   order by created_at
   limit 50;
$$;

create or replace function public.mark_notices_read(p_ids uuid[])
returns void
language sql
security definer
set search_path = ''
as $$
  update public.user_notices set read_at = now()
   where user_id = (select auth.uid()) and id = any (p_ids) and read_at is null;
$$;

create or replace function public.admin_delete_photo(p_photo uuid, p_reason text default null)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_path text;
  v_user uuid;
begin
  perform private.require_admin();
  if nullif(btrim(p_reason), '') is null then
    raise exception 'reason_required: say why the photo was removed' using errcode = 'P0001';
  end if;
  delete from public.profile_photos where id = p_photo returning storage_path, user_id into v_path, v_user;
  if v_path is null then raise exception 'not_found' using errcode = 'P0001'; end if;
  insert into public.user_notices (user_id, title, body)
  values (v_user, 'A photo was removed', left('Reason: ' || btrim(p_reason) || '. Please add a photo that follows our guidelines.', 500));
  perform private.audit('photo:delete', v_user, v_path, jsonb_build_object('reason', p_reason));
  return v_path;
end;
$$;

revoke all on function public.get_my_notices(), public.mark_notices_read(uuid[]), public.admin_delete_photo(uuid, text)
  from public, anon;
grant execute on function public.get_my_notices(), public.mark_notices_read(uuid[]), public.admin_delete_photo(uuid, text)
  to authenticated;
