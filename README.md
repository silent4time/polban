# پل‌بان (Polban)

پل امن بین فروشگاه وردپرس و پنل‌های بالادستی که هاست فروشگاه مستقیم به آن‌ها دسترسی ندارد.

نسخه فعلی را در فایل `VERSION` ببینید.

## نصب تک‌خطی

روی سرور لینوکس (root):

```bash
curl -fsSL https://raw.githubusercontent.com/silent4time/polban/main/get.sh | sudo bash
```

بعد از اجرا منوی مدیریت باز می‌شود (نصب تازه، به‌روزرسانی، وضعیت، مسیر پنل).

ریپو خصوصی است؛ یکی از این‌ها لازم است:

- متغیر محیطی `GH_TOKEN` با دسترسی خواندن ریپو، یا
- `gh auth login` روی همان سرور

نصب‌کننده از شما می‌پرسد: مسیر نصب، آدرس عمومی سرویس، رمز پنل وب، کلید API (یا ساخت خودکار)، و در صورت تمایل اولین مبدأ مجاز پنل.

## مدیریت

```bash
sudo polban            # menu
sudo polban status     # status (API key is never printed)
sudo polban update     # git fetch + reset --hard origin/main, then install.sh --update
sudo polban url        # admin panel URL
```

Menu (English):

1. Fresh install / reconfigure (asks for `yes` if config.php exists)
2. Update (git fetch + reset, keep config)
3. Status
4. Show admin panel URL
5. Exit

`install.sh` بدون آرگومان منو را باز می‌کند؛ `--install` نصب تازه و `--update` (یا `-y`) به‌روزرسانی مستقیم.
به‌روزرسانی `config.php` را دست نمی‌زند (فقط timeout کمتر از ۶۰ به ۶۰ می‌رسد و مجوز `root:www-data 660` تنظیم می‌شود)، storage حفظ می‌شود و vhost آپاچی بازنویسی نمی‌شود.
کلید API هرگز چاپ نمی‌شود: `sudo grep api_key /home/polban/config.php`

## ارتقا از نسخه‌های 1.0.x (باینری کپی‌شده / سورس تغییر‌یافته)

اگر `polban` نسخه را `?` نشان می‌دهد یا `git pull` با خطای «local changes» شکست می‌خورد:

```bash
sudo git -C /opt/polban-src config core.fileMode false
sudo git -C /opt/polban-src fetch origin
sudo git -C /opt/polban-src reset --hard origin/main
sudo bash /opt/polban-src/install.sh --update
```

بعد از آن `/usr/local/bin/polban` یک symlink به `/home/polban/bin/polban` است و از این به بعد `sudo polban update` کافی است.

## API

- `GET /v1/health` — سلامت  
- `POST /v1/proxy` — هدر `X-Polban-Key`؛ بدنه JSON:

```json
{
  "method": "POST",
  "url": "https://panel.example.com:8443/api/admin/token",
  "headers": { "Content-Type": "application/x-www-form-urlencoded" },
  "body": "username=admin&password=secret"
}
```

فقط originهایی که در allowlist پنل وب یا نصب ثبت شده‌اند قبول می‌شوند.

## اتصال به وردپرس

در افزونهٔ «کاریونیت — ابزار شبکه» آدرس پل‌بان و کلید API را وارد کنید و برای پنل‌های موردنظر گزینهٔ «از طریق پل‌بان» را روشن کنید.

## امنیت

- `config.php` را commit نکنید  
- مسیر پنل وب تصادفی است (`pb-…`)  
- کلید API را فقط در هاست فروشگاه و این سرویس نگه دارید  
