# Release checklist

- For the final public desktop build, Yandex.Disk connection must work out of the box for a new user. Do not require users to create or find `.env` files with `YANDEX_CLIENT_ID` / `YANDEX_CLIENT_SECRET`.
- Current development builds may read credentials from `web_app/.env`, `~/.passport_creator/.env`, or environment variables.
- Final production path: either embed release OAuth credentials during build or route the OAuth code exchange through the Passport creator server so users only click "Connect Yandex.Disk".
