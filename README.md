# Easy Conduit Installer & Manager

![Shell Script](https://img.shields.io/badge/Language-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)
![Docker](https://img.shields.io/badge/Container-Docker-2496ED?style=flat-square&logo=docker&logoColor=white)
![OS](https://img.shields.io/badge/OS-Ubuntu%20%7C%20Debian%20%7C%20CentOS%20%7C%20Fedora-lightgrey?style=flat-square)

[English](#english) | [فارسی](#persian)

---

<a name="english"></a>
## 🇬🇧 English Description

**Easy Conduit** is a fully automated, production-ready Bash script designed to deploy and manage the **Conduit Proxy** server on Linux systems. It handles the entire stack setup, including Docker installation, system resource optimization (auto-swap), and advanced security configurations.

One of the key features of this installer is the built-in **Geo-fencing capability**, which leverages `ipset` and `iptables` to restrict access strictly to Iranian IP addresses (configurable), ensuring security and compliance for specific use cases.

### ✨ Key Features
* **Zero-Config Deployment:** Installs Docker, Docker Compose, and all system dependencies automatically.
* **Smart Resource Management:** Automatically detects available RAM and creates a **2GB Swap file** if memory is below 1.9GB to prevent OOM kills.
* **Geo-Fencing Security:** Optional blocking of non-Iran IPs using `ipset` (high performance) with daily auto-updates via Cronjob.
* **Permission Fixes:** Automatically handles directory permissions (`chmod 777`) for the data volume to ensure the container can write keys/logs without issues.
* **Management CLI:** Includes a custom `conduit` command-line tool for easy management.

### 🚀 Quick Installation

Run the following command as **root** to install:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/mhrezaei/easy-conduit/main/install.sh)

```

### ⚙️ Interactive Configuration

During installation, the script will ask:

1. **Restrict to Iran IPs?** (`y`/`n`) - Defaults to `y`.
2. **Max Clients:** Limit concurrent connections (Default: `200`).
3. **Bandwidth Limit:** Set Mbps limit per user/global (Default: `5` Mbps).
4. **Port:** The listening port for the proxy (Default: `443`).

### 🛠 Management CLI (`conduit`)

After installation, use the `conduit` command to manage the service:

| Command | Description |
| --- | --- |
| `conduit status` | Check container status and real-time resource usage (CPU/RAM). |
| `conduit logs` | View live logs from the proxy container. |
| `conduit restart` | Restart the service and re-apply firewall rules. |
| `conduit content` | List files in the data directory (view keys/configs). |
| `conduit update-ips` | Force update the Geo-IP whitelist database immediately. |
| `conduit uninstall` | Completely remove the service, data, and scripts. |

---

<a name="persian"></a>

## 🇮🇷 توضیحات فارسی

**Easy Conduit** یک اسکریپت نصب‌کننده خودکار و پیشرفته برای راه‌اندازی **Conduit Proxy** است. این ابزار با نگاهی به نیازهای محیط عملیاتی (Production) طراحی شده و تمامی مراحل نصب داکر، تنظیمات شبکه و بهینه‌سازی سیستم عامل را به صورت خودکار انجام می‌دهد.

ویژگی اصلی این نصب‌کننده، سیستم **Geo-fencing** داخلی است که با استفاده از `ipset` و `iptables`، امکان محدود کردن دسترسی به پورت سرویس را تنها برای آی‌پی‌های ایران فراهم می‌کند. این قابلیت امنیت سرویس را به شدت افزایش می‌دهد.

### ✨ ویژگی‌های کلیدی

* **نصب بدون دردسر:** نصب خودکار Docker، Docker Compose و تمامی پیش‌نیازهای سیستمی.
* **مدیریت هوشمند منابع:** بررسی رم سرور و ایجاد خودکار **2GB Swap** در صورتی که رم کمتر از 1.9 گیگابایت باشد (جلوگیری از کرش کردن سرویس).
* **فایروال جغرافیایی:** امکان محدودسازی دسترسی فقط به آی‌پی‌های ایران با آپدیت روزانه و خودکار لیست آی‌پی‌ها.
* **اصلاح دسترسی‌ها (Permission Fix):** رفع مشکل دسترسی فایل‌ها در داکر با تنظیم صحیح سطح دسترسی پوشه Data.
* **ابزار مدیریت خط فرمان:** ارائه دستور `conduit` برای مدیریت آسان سرویس پس از نصب.

### 🚀 نصب سریع

برای نصب، دستور زیر را با دسترسی **root** اجرا کنید:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/mhrezaei/easy-conduit/main/install.sh)

```

### ⚙️ تنظیمات نصب

در حین نصب، سوالات زیر پرسیده می‌شود:

1. **محدودسازی به ایران؟** (`y`/`n`) - پیش‌فرض: `y` (پیشنهاد می‌شود).
2. **حداکثر کاربر:** تعداد کانکشن‌های همزمان (پیش‌فرض: `200`).
3. **محدودیت پهنای باند:** بر حسب مگابیت (پیش‌فرض: `5`).
4. **پورت:** پورت اجرایی سرویس (پیش‌فرض: `443`).

### 🛠 راهنمای دستورات (`conduit`)

پس از نصب، می‌توانید از دستور `conduit` در ترمینال استفاده کنید:

| دستور | توضیحات |
| --- | --- |
| `conduit status` | مشاهده وضعیت کانتینر و مقدار مصرف رم و پردازنده. |
| `conduit logs` | مشاهده لاگ‌های لحظه‌ای پروکسی. |
| `conduit restart` | ریستارت سرویس و اعمال مجدد قوانین فایروال. |
| `conduit content` | نمایش لیست فایل‌های موجود در دایرکتوری دیتا (کلیدها و ...). |
| `conduit update-ips` | بروزرسانی دستی و فوری لیست آی‌پی‌های مجاز ایران. |
| `conduit uninstall` | حذف کامل سرویس، فایل‌ها و اسکریپت‌ها از سرور. |

---

Developed & Maintained by [mhrezaei](https://github.com/mhrezaei)
