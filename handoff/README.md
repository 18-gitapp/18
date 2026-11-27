# پوشه‌ی handoff

هر `*.sh` اینجا **درست موقع تحویل شیفت** (بعد از رفتن ریپو به اکانت بعدی و قبل از استارتش) اجرا میشه، به ترتیب نام.
`gh` (GitHub CLI) با توکن `GH_TOKEN` خودت لاگینه، پس می‌تونی روی ریپوی بعدی هر کاری بکنی.

متغیرهای در دسترس: `$NEXT_REPO` (= ریپوی هدف، مثل `reza/x`)، `$SELF_REPO`، `$DATA_DIR`، و **همه‌ی Secretهای فعلی** به‌صورت متغیر.

```bash
# نمونه‌ها (داخل یک فایل handoff/10-sync.sh)
gh variable set RUN_MINUTES --body 240 --repo "$NEXT_REPO"          # طول شیفت اکانت بعدی
gh secret set API_KEY --body "$API_KEY" --repo "$NEXT_REPO"          # سکرت فعلی رو دوباره ست کن
gh secret delete OLD_KEY --repo "$NEXT_REPO"                         # حذف
```

> ⚠️ مقدار سکرت رو **داخل خود اسکریپت ننویس** — فایل‌های این پوشه داخل ریپو commit میشن (plaintext).
> برای مقدارهایی که وسط شیفت می‌سازی از دستور `handoff-set` استفاده کن:
>
> ```bash
> handoff-set secret MY_NEW_TOKEN "مقدار"      # یا:  echo -n مقدار | handoff-set secret MY_NEW_TOKEN
> handoff-set var    MODE night
> handoff-set list
> ```
> این مقدارها فقط روی دیسک موقت ماشین می‌مونن (هیچ‌جا commit یا بکاپ نمیشن) و موقع تحویل روی ریپوی بعدی ست میشن.

## اجرای یک‌بار یا هر بار؟

| فایل | رفتار |
|---|---|
| `handoff/20-sync.sh` | **هر تحویل** اجرا میشه (مناسب کارهای idempotent) |
| `handoff/20-sync.once.sh` | **فقط یک‌بار**؛ بعد از اجرا از ریپو حذف میشه و دفعه‌ی بعد تکرار نمیشه |
| `handoff-set secret/var ...` | **فقط یک‌بار**؛ بعد از ست موفق پاک میشه |

نیاز: Secret `GH_TOKEN` (توکن classic با scope `repo`). خطای یک hook مانع تحویل نمیشه. فایل‌های `*.example` اجرا نمیشن.
