# Email setup (verification, forgot password, change email)

The app uses **6-digit codes typed into the app** (no links, so no domain,
website or deep link is needed). Do these once in the Supabase dashboard.

## 1. Custom SMTP (required)
Supabase's built-in mailer only sends ~2 emails/hour and only to your own
team members. Set your own sender at
**Authentication -> Emails -> SMTP Settings -> Enable custom SMTP**.

Free options that need NO domain:
* **Gmail** (500/day): turn on 2-Step Verification, create an *App password*
  (myaccount.google.com/apppasswords). Host `smtp.gmail.com`, port `465`,
  user = your Gmail, pass = the 16-character app password, sender = your Gmail,
  sender name = `Vitrax`.
* **Brevo** (300/day free): create an SMTP key, host `smtp-relay.brevo.com`,
  port `587`.
Later, with a domain: Resend / Brevo / Postmark with SPF + DKIM.

After enabling custom SMTP: **Authentication -> Rate Limits** -> raise
"Rate limit for sending emails" (e.g. 30/hour).

## 2. Settings
**Authentication -> Sign In / Providers -> Email**
* Confirm email: **ON** (this is the email verification).
* Secure email change: **OFF** (otherwise a code goes to BOTH the old and new
  address and the user would need both).
* Email OTP expiration: 3600 s, OTP length: 6.

## 3. Email templates (Authentication -> Emails -> Templates)
Replace the link with the code `{{ .Token }}`:

**Confirm signup** – subject `Your Vitrax verification code`
```
<h2>Verify your email</h2>
<p>Your Vitrax code is:</p>
<h1 style="letter-spacing:8px">{{ .Token }}</h1>
<p>Enter it in the app. It expires in 1 hour. If you didn't sign up, ignore this email.</p>
```

**Reset password** – subject `Reset your Vitrax password`
```
<h2>Reset your password</h2>
<p>Your Vitrax reset code is:</p>
<h1 style="letter-spacing:8px">{{ .Token }}</h1>
<p>Enter it in the app. It expires in 1 hour. If you didn't ask for this, ignore this email.</p>
```

**Change email address** – subject `Confirm your new Vitrax email`
```
<h2>Confirm your new email</h2>
<p>Your Vitrax code is:</p>
<h1 style="letter-spacing:8px">{{ .Token }}</h1>
<p>Enter it in the app to finish changing your email.</p>
```

## 4. Existing accounts
Turning "Confirm email" ON does not affect accounts that already signed in.
Unconfirmed test users must verify (Resend on the sign-in screen) or be
confirmed by hand in Authentication -> Users.

## 5. Test checklist
1. Register with a real email -> code arrives -> enter it -> lands in the app.
2. Sign out, "Forgot password?" -> code -> new password -> sign in with it.
3. You -> Edit profile -> Change email -> code to the NEW address -> done.
4. You -> Edit profile -> Change password (asks for the current password).
