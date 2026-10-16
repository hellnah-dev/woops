-- Tiny assertion helpers for the security tests (test database only).
create schema tests;
grant usage on schema tests to anon, authenticated, service_role;

create table tests.results (id serial primary key, name text, passed boolean, detail text);
grant insert, select on tests.results to anon, authenticated, service_role;
grant usage on sequence tests.results_id_seq to anon, authenticated, service_role;

create function tests.ok(p_cond boolean, p_name text) returns void language plpgsql as $$
begin
  insert into tests.results (name, passed, detail)
  values (p_name, coalesce(p_cond, false), case when p_cond then null else 'condition was false/null' end);
end $$;

-- Runs `p_sql` as the current role and asserts it raises an error whose
-- message matches `p_pattern` (ILIKE).
create function tests.throws(p_sql text, p_pattern text, p_name text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    insert into tests.results (name, passed, detail)
    values (p_name, sqlerrm ilike p_pattern, sqlerrm);
    return;
  end;
  insert into tests.results (name, passed, detail) values (p_name, false, 'no error raised');
end $$;

-- Switch "logged in" user for subsequent statements.
create function tests.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), false);
$$;

-- Completes a test profile (2 photos, bio, 3 interests, age confirmed) so it may swipe.
create function tests.make_ready(p_user uuid) returns void language sql as $$
  insert into public.profile_photos (user_id, storage_path) values (p_user, p_user::text || '/ready.jpg');
  update public.profiles set bio = coalesce(nullif(bio, ''), 'Hello'), age_verified = true where id = p_user;
  insert into public.profile_interests (user_id, interest_id)
  select p_user, id from public.interests order by id limit 3
  on conflict do nothing;
$$;

grant execute on all functions in schema tests to anon, authenticated, service_role;
