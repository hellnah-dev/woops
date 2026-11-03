"""Generates Woops's branded Supabase Auth email templates.

Run from the project root:  python3 tools/make_email_templates.py
Writes supabase/templates/*.html. Each uses Supabase template variables
({{ .ConfirmationURL }}, {{ .Token }}, {{ .Email }}, {{ .NewEmail }}).

Design: email-safe table layout with inline styles (Gmail, Outlook, Apple
Mail), a solid-colour fallback wherever a gradient is used, a plain link under
every button, and a dark-mode variant.
"""
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "supabase" / "templates"
SUPPORT = "https://kamaucha.me/rammy24d"

LAYOUT = """<!doctype html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>{title}</title>
<link href="https://fonts.googleapis.com/css2?family=Pacifico&family=Nunito:wght@400;700;800&display=swap" rel="stylesheet">
<style>
  body {{ margin:0; padding:0; background:#FFF0F5; }}
  a {{ color:#E8336D; }}
  @media (max-width:600px) {{ .card {{ width:100% !important; border-radius:0 !important; }} .pad {{ padding:28px 22px !important; }} }}
  @media (prefers-color-scheme: dark) {{
    body, .bg {{ background:#1C1119 !important; }}
    .card {{ background:#2A1724 !important; }}
    .text {{ color:#F6E9EF !important; }}
    .muted {{ color:#C9B3BF !important; }}
    .box {{ background:#3A2232 !important; border-color:#5A3249 !important; }}
  }}
</style>
</head>
<body style="margin:0;padding:0;background:#FFF0F5;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">{preheader}</div>
<table role="presentation" class="bg" width="100%" cellpadding="0" cellspacing="0" style="background:#FFF0F5;">
<tr><td align="center" style="padding:32px 12px;">
  <table role="presentation" class="card" width="560" cellpadding="0" cellspacing="0"
         style="width:560px;max-width:560px;background:#FFFFFF;border-radius:24px;overflow:hidden;
                box-shadow:0 12px 40px rgba(255,79,129,0.18);">
    <tr><td align="center" bgcolor="#FF4F81"
            style="background:#FF4F81;background-image:linear-gradient(135deg,#FF7EB3 0%,#FF4F81 55%,#FF8A7A 100%);
                   padding:34px 24px 28px;">
      <div style="font-family:'Pacifico','Brush Script MT',cursive;font-size:42px;line-height:64px;color:#FFFFFF;">Woops</div>
      <div style="font-family:'Nunito',Arial,sans-serif;font-size:14px;color:#FFE6EF;letter-spacing:0.3px;padding-top:6px;">Find your someone</div>
    </td></tr>
    <tr><td class="pad" style="padding:36px 40px 12px;font-family:'Nunito',Arial,sans-serif;">
      <h1 class="text" style="margin:0 0 12px;font-size:26px;line-height:32px;font-weight:800;color:#2B1A24;">{heading}</h1>
      <p class="muted" style="margin:0 0 26px;font-size:16px;line-height:25px;color:#6B5562;">{intro}</p>
      {action}
      <p class="muted" style="margin:26px 0 0;font-size:14px;line-height:22px;color:#8A7180;">{after}</p>
    </td></tr>
    <tr><td class="pad" style="padding:20px 40px 32px;font-family:'Nunito',Arial,sans-serif;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
        <tr><td class="box" style="background:#FFF5F8;border:1px solid #FFD6E3;border-radius:14px;padding:14px 16px;">
          <p class="muted" style="margin:0;font-size:13px;line-height:20px;color:#7A6270;">
            🔒 <b>Stay safe:</b> Woops will never ask for your password, codes or payment details by email or in chat.
          </p>
        </td></tr>
      </table>
    </td></tr>
  </table>
  <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="width:560px;max-width:100%;">
    <tr><td align="center" style="padding:20px 16px;font-family:'Nunito',Arial,sans-serif;font-size:12px;line-height:19px;color:#A38D99;">
      You're getting this because someone used {{{{ .Email }}}} on Woops. If it wasn't you, you can ignore this email.<br>
      Woops is for adults 18+. · <a href="{support}" style="color:#E8336D;text-decoration:none;">Help &amp; support</a><br>
      © HellNah · Woops by rammy24d
    </td></tr>
  </table>
</td></tr>
</table>
</body>
</html>
"""

def button(label: str) -> str:
    return f"""<table role="presentation" cellpadding="0" cellspacing="0" align="center" style="margin:0 auto;">
        <tr><td align="center" bgcolor="#FF4F81" style="border-radius:999px;background:#FF4F81;
                  background-image:linear-gradient(135deg,#FF7EB3 0%,#FF4F81 55%,#FF8A7A 100%);
                  box-shadow:0 8px 20px rgba(255,79,129,0.35);">
          <a href="{{{{ .ConfirmationURL }}}}" target="_blank"
             style="display:inline-block;padding:16px 38px;font-family:'Nunito',Arial,sans-serif;font-size:17px;
                    font-weight:800;color:#FFFFFF;text-decoration:none;border-radius:999px;">{label}</a>
        </td></tr>
      </table>
      <p class="muted" style="margin:22px 0 0;font-size:13px;line-height:20px;color:#8A7180;text-align:center;">
        Button not working? Copy this link into your browser:<br>
        <a href="{{{{ .ConfirmationURL }}}}" style="color:#E8336D;word-break:break-all;">{{{{ .ConfirmationURL }}}}</a>
      </p>"""

CODE = """<table role="presentation" cellpadding="0" cellspacing="0" align="center" style="margin:0 auto;">
        <tr><td class="box" align="center" style="background:#FFF5F8;border:2px dashed #FF9BBB;border-radius:16px;padding:18px 34px;">
          <span class="text" style="font-family:'Courier New',monospace;font-size:34px;letter-spacing:10px;font-weight:700;color:#2B1A24;">{{ .Token }}</span>
        </td></tr>
      </table>"""

TEMPLATES = {
    "confirmation": dict(
        subject="Confirm your Woops account 💌",
        title="Confirm your email",
        preheader="One tap to confirm your email and start meeting people.",
        heading="Welcome to Woops! 💕",
        intro="You're one tap away. Confirm your email so we know it's really you, then finish your profile and start meeting people.",
        action=button("Confirm my email"),
        after="This link works once and expires in 24 hours. Open it on the phone where you signed up.",
    ),
    "recovery": dict(
        subject="Reset your Woops password",
        title="Reset your password",
        preheader="Here's your link to choose a new password.",
        heading="Forgot your password?",
        intro="No worries, it happens. Tap the button to choose a new password for your Woops account.",
        action=button("Choose a new password"),
        after="This link expires in 1 hour. If you didn't ask to reset your password, ignore this email; your account is safe.",
    ),
    "magic_link": dict(
        subject="Your Woops sign-in link ✨",
        title="Your sign-in link",
        preheader="Tap to sign in to Woops, no password needed.",
        heading="Here's your sign-in link",
        intro="Tap the button to sign in to Woops. No password needed.",
        action=button("Sign in to Woops"),
        after="This link works once and expires in 1 hour. Didn't request it? You can safely ignore this email.",
    ),
    "email_change": dict(
        subject="Confirm your new email for Woops",
        title="Confirm your new email",
        preheader="Confirm the new email address for your Woops account.",
        heading="Confirm your new email",
        intro="You asked to change your Woops email to <b>{{ .NewEmail }}</b>. Tap the button to confirm.",
        action=button("Confirm new email"),
        after="If you didn't ask for this change, ignore this email and consider changing your password.",
    ),
    "invite": dict(
        subject="You're invited to Woops 💗",
        title="You're invited",
        preheader="You've been invited to join Woops.",
        heading="You're invited to Woops!",
        intro="Someone thinks you'd love Woops, the dating app for genuine connections. Tap below to accept and create your account.",
        action=button("Accept invite"),
        after="Woops is for adults 18+ (or older where local law requires).",
    ),
    "reauthentication": dict(
        subject="Your Woops security code",
        title="Your security code",
        preheader="Use this code to confirm it's you.",
        heading="Confirm it's you",
        intro="Enter this code in Woops to continue:",
        action=CODE,
        after="The code expires in 10 minutes. Never share it with anyone, not even someone who says they're from Woops.",
    ),
}

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for name, t in TEMPLATES.items():
        html = LAYOUT.format(support=SUPPORT, **{k: v for k, v in t.items() if k != "subject"})
        (OUT / f"{name}.html").write_text(html, encoding="utf-8")
        print(f"{name:<18} {t['subject']}")
