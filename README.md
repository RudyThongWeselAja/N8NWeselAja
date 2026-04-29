# XenithPay n8n Workflow Template

Template ini berisi workflow n8n untuk integrasi XenithPay. Paketnya sudah siap untuk sandbox, lalu bisa dipindah ke production dengan mengganti credential XenithPay dan nilai `xenithpayEndpoint` di tabel `variables`.

Semua setup database sekarang dipusatkan di `xenithpay_database_setup.sql`. File itu membuat schema transaksi, tabel variables, lookup channel, dan seed channel bawaan.

- `payment_channels`
- `payout_channels`
- `variables`
- `invoices`
- `payouts`

Lalu mengisi seed channel dan starter row untuk konfigurasi workflow.

## Isi Paket

| File | Keterangan |
| --- | --- |
| `Xenithpay Template.json` | Workflow n8n yang di-import ke instance n8n. |
| `xenithpay_database_setup.sql` | Setup tabel database workflow: `variables`, `invoices`, `payouts`, `payment_channels`, dan `payout_channels`, plus seed bawaan. |
| `README.md` | Panduan setup dan penggunaan workflow. |

## Prasyarat

| Komponen | Keterangan |
| --- | --- |
| n8n | Self-hosted atau cloud instance yang mendukung workflow JSON ini. |
| PostgreSQL | Dipakai untuk lookup channel, variabel workflow, dan tabel transaksi aplikasi Anda. |
| SMTP | Dipakai untuk email invoice dan notifikasi transaksi. |
| Public URL | Domain publik atau tunnel seperti ngrok agar callback XenithPay bisa masuk ke n8n. |
| XenithPay | Akun sandbox atau production, lengkap dengan API key dan secret yang sesuai. |

## Pembuatan Database PostgreSQL

Workflow ini butuh satu database PostgreSQL yang bisa diakses dari n8n. Contoh di bawah memakai nama database `xenithpay` dan user `xenithpay_user`; silakan ganti sesuai standar deployment Anda.

### 1. Buat database dan user

Jalankan perintah ini dari user PostgreSQL yang punya akses membuat database, misalnya `postgres`:

```bash
psql -h <host> -U postgres
```

Lalu jalankan SQL berikut:

```sql
CREATE USER xenithpay_user WITH PASSWORD '<strong-password>';
CREATE DATABASE xenithpay OWNER xenithpay_user;
```

Jika database sudah dibuat oleh provider hosting, cukup pastikan Anda punya nilai koneksi berikut:

| Field | Contoh |
| --- | --- |
| Host | `db.example.com` |
| Port | `5432` |
| Database | `xenithpay` |
| User | `xenithpay_user` |
| Password | password database |
| Schema | `public` |

### 2. Jalankan setup SQL

Dari folder repo ini, jalankan file `xenithpay_database_setup.sql` ke database yang sudah dibuat:

```bash
psql -h <host> -p 5432 -U xenithpay_user -d xenithpay -f xenithpay_database_setup.sql
```

File ini aman dijalankan ulang karena memakai `CREATE TABLE IF NOT EXISTS`, `CREATE UNIQUE INDEX IF NOT EXISTS`, dan `ON CONFLICT` untuk seed channel.

### 3. Isi variable environment

Setelah tabel dibuat, ganti placeholder di tabel `public.variables`:

```sql
UPDATE public.variables
SET value = CASE key
  WHEN 'xenithpayEndpoint' THEN 'https://openapi.sandbox.xenithpay.com'
  WHEN 'n8nURL' THEN 'https://n8n.example.com'
  WHEN 'homepageURL' THEN 'https://www.example.com'
END
WHERE key IN ('xenithpayEndpoint', 'n8nURL', 'homepageURL');
```

Untuk production, ubah `xenithpayEndpoint` menjadi:

```text
https://openapi.xenithpay.com
```

### 4. Cek hasil setup

Gunakan query ini untuk memastikan tabel, variable, dan seed channel sudah masuk:

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'variables',
    'invoices',
    'payouts',
    'payment_channels',
    'payout_channels'
  )
ORDER BY table_name;

SELECT 'payment_channels' AS table_name, COUNT(*) AS total_rows
FROM public.payment_channels
UNION ALL
SELECT 'payout_channels' AS table_name, COUNT(*) AS total_rows
FROM public.payout_channels;

SELECT key, value
FROM public.variables
ORDER BY key;
```

Hasil yang diharapkan:

| Data | Minimal hasil |
| --- | --- |
| Tabel | 5 tabel muncul: `variables`, `invoices`, `payouts`, `payment_channels`, `payout_channels`. |
| `payment_channels` | 14 row seed channel payin. |
| `payout_channels` | 31 row seed channel payout. |
| `variables` | 3 key: `homepageURL`, `n8nURL`, `xenithpayEndpoint`. |

### 5. Hubungkan ke credential n8n

Buat credential PostgreSQL di n8n dengan nama `database`, lalu isi sesuai koneksi database:

| Field n8n | Isi |
| --- | --- |
| Host | Host PostgreSQL Anda. |
| Database | `xenithpay` atau nama database yang Anda pakai. |
| User | `xenithpay_user` atau user database Anda. |
| Password | Password user database. |
| Port | Biasanya `5432`. |
| SSL | Aktifkan kalau provider database mewajibkan SSL. |

Kalau muncul error `permission denied for schema public`, pastikan database dimiliki oleh user yang dipakai n8n atau jalankan grant berikut dari user admin:

```sql
GRANT USAGE, CREATE ON SCHEMA public TO xenithpay_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO xenithpay_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO xenithpay_user;
```

## Setup Cepat

1. Buat database PostgreSQL dengan panduan di bagian `Pembuatan Database PostgreSQL`.
2. Jalankan setup SQL:

```bash
psql -h <host> -p 5432 -U <user> -d <database> -f xenithpay_database_setup.sql
```

3. Ganti placeholder di tabel `public.variables` sesuai domain dan environment Anda.
4. Import `Xenithpay Template.json` ke n8n.
5. Buat credential yang dipakai workflow:
   - `Xenith-Api-Key`
   - `Xenith-Secret-Key`
   - `xenith-web-signature-secret`
   - `database`
   - `SMTP`
6. Aktifkan workflow, lalu gunakan webhook yang dibutuhkan.

## Credentials n8n

| Credential | Tipe | Dipakai untuk |
| --- | --- | --- |
| `Xenith-Api-Key` | HTTP Header Auth | Header autentikasi request ke XenithPay. |
| `Xenith-Secret-Key` | Crypto HMAC | Signature request payin, payout, dan simulator. |
| `xenith-web-signature-secret` | Crypto HMAC | Validasi signature callback dari XenithPay. |
| `database` | PostgreSQL | Query lookup table dan tabel transaksi. |
| `SMTP` | SMTP | Mengirim invoice dan notifikasi email. |

Nama credential di atas mengikuti nama yang sudah dipakai di workflow. Kalau nama credential di instance n8n Anda berbeda, pilih ulang credential pada node terkait setelah import.

## Tabel `variables`

Workflow tidak lagi memakai community node `n8n-nodes-globals`. Semua variabel runtime sekarang dibaca dari tabel PostgreSQL `public.variables`.

Nilai awal dari file SQL sengaja memakai placeholder:

```sql
INSERT INTO public.variables (key, value) VALUES
  ('xenithpayEndpoint', '<xenithpay-api>'),
  ('n8nURL', '<your-n8n-url>'),
  ('homepageURL', '<your-homepage-url>')
ON CONFLICT (key) DO UPDATE
SET value = EXCLUDED.value;
```

Setelah menjalankan `xenithpay_database_setup.sql`, ganti placeholder tersebut di database:

```sql
UPDATE public.variables
SET value = CASE key
  WHEN 'xenithpayEndpoint' THEN 'https://openapi.sandbox.xenithpay.com'
  WHEN 'n8nURL' THEN 'https://n8n.example.com'
  WHEN 'homepageURL' THEN 'https://www.example.com'
END
WHERE key IN ('xenithpayEndpoint', 'n8nURL', 'homepageURL');
```

Keterangan tiap key:

| Key | Keterangan |
| --- | --- |
| `xenithpayEndpoint` | Ganti `<xenithpay-api>` dengan base URL XenithPay. Sandbox pakai `https://openapi.sandbox.xenithpay.com`, production pakai `https://openapi.xenithpay.com`. |
| `n8nURL` | Ganti `<your-n8n-url>` dengan public base URL n8n, misalnya domain production atau ngrok. Jangan pakai trailing slash. |
| `homepageURL` | Ganti `<your-homepage-url>` dengan URL tujuan tombol `Kembali ke Beranda` pada halaman status pembayaran. |

Nilai turunan yang dibentuk otomatis oleh workflow:

- Callback payin: `n8nURL + /webhook/xenith-payin`
- Callback payout: `n8nURL + /webhook/xenith-payout`
- Redirect status pembayaran: `n8nURL + /webhook/payment?referenceCode=...`

Jadi tidak ada lagi key terpisah seperti `callbackUrlPayin`, `callbackUrlPayout`, atau `redirectUrl`.

## Bedakan 2 Mode

Ada dua hal yang sering ketuker:

| Layer | Sandbox / Test | Production | Diatur dari | Dampak |
| --- | --- | --- | --- | --- |
| XenithPay | `https://openapi.sandbox.xenithpay.com` | `https://openapi.xenithpay.com` | `xenithpayEndpoint` dan credential XenithPay | Menentukan request API dikirim ke environment XenithPay yang mana. |
| n8n Webhook | `/webhook-test/...` | `/webhook/...` | Mode webhook di n8n | Menentukan trigger masuk ke editor test atau workflow aktif. |

Ringkasnya:

- `xenithpayEndpoint` menentukan sandbox atau production di sisi XenithPay.
- `/webhook-test/` vs `/webhook/` hanya menentukan mode webhook n8n.
- Callback dari XenithPay harus selalu diarahkan ke `/webhook/...`, bukan `/webhook-test/...`.

Kombinasi yang paling umum:

| Kombinasi | Kapan dipakai | Catatan |
| --- | --- | --- |
| XenithPay sandbox + n8n production webhook | Uji end-to-end callback | Ini setup paling umum saat development. API masih sandbox, tapi callback tetap masuk ke workflow aktif. |
| XenithPay sandbox + n8n test webhook | Tes manual dari browser atau Postman | Cocok saat `Listen for test event`, tapi bukan untuk callback otomatis dari XenithPay. |
| XenithPay production + n8n production webhook | Live production | Pakai endpoint dan credential production. |

## Database

Template ini mengandalkan schema dari `xenithpay_database_setup.sql`:

| Tabel | Dipakai oleh | Isi |
| --- | --- | --- |
| `variables` | Create Invoice, Create Payout, Payment Status Page | Konfigurasi environment dan base URL workflow. |
| `invoices` | Create Invoice, Callback Payin, Payment Status Page | Data transaksi payin dan status invoice. |
| `payouts` | Create Payout, Callback Payout | Data transaksi payout/disbursement. |
| `payment_channels` | Create Invoice / Payin | 14 channel payin: QRIS, VA, dan e-wallet. |
| `payout_channels` | Create Payout | 31 channel payout: bank transfer dan e-wallet. |

File SQL tersebut melakukan:

- `CREATE TABLE IF NOT EXISTS public.variables`
- `CREATE TABLE IF NOT EXISTS public.invoices`
- `CREATE TABLE IF NOT EXISTS public.payouts`
- `CREATE TABLE IF NOT EXISTS public.payment_channels`
- `CREATE TABLE IF NOT EXISTS public.payout_channels`
- Membuat unique key channel untuk tabel payin dan payout
- Mengisi seed `payment_channels` dan `payout_channels`
- Mengisi starter row `variables` tanpa menimpa nilai yang sudah Anda ubah

Struktur lookup table channel:

| Kolom | Tipe | Keterangan |
| --- | --- | --- |
| `method` | VARCHAR(64) | Metode XenithPay, misalnya `QR_CODE`, `VIRTUAL_ACCOUNT`, `BANK_TRANSFER`, atau `EWALLET`. |
| `channel` | VARCHAR(64) | Kode channel unik yang dikirim dari query parameter webhook. |
| `name` | VARCHAR(160) | Nama channel untuk dibaca manusia. |

Struktur tabel `variables`:

| Kolom | Tipe | Keterangan |
| --- | --- | --- |
| `key` | text | Nama variabel workflow. Menjadi primary key. |
| `value` | text | Nilai variabel. |

Tabel `invoices` dan `payouts` juga sudah dibuat oleh file SQL ini, termasuk `reference_code` unique key untuk mencegah duplikasi transaksi dari input webhook.

## Flow Workflow

### 1. Create Invoice / Payin

Flow ini membuat invoice pembayaran baru, mengambil variabel workflow dari tabel `variables`, mengambil mapping channel dari `payment_channels`, membuat signature HMAC, mengirim request ke XenithPay, lalu mengirim email invoice ke customer.

Alur node:

```text
Webhook: Create Invoice
> Postgres: Get Payin Variables
> Aggregate: Payin Variables
> Code: Map Payin Variables
> Postgres: Check Existing Invoice
> Check: Invoice Reference Available?
> Postgres: Get Payment Channel
> Code: Build Xenith Payin Requests
> Crypto: Create Xenith Payin Signature
> Crypto: Generate Payin Idempotency Key
> HTTP: Create Xenith Payin
> Email: Send Invoice Payment Options
> Postgres: Insert Invoice
```

Output false dari `Check: Invoice Reference Available?` diarahkan ke `Code: Build Invoice Duplicate Response`.

Penjelasan node:

| Node | Fungsi |
| --- | --- |
| `Webhook: Create Invoice` | Menerima request GET untuk membuat invoice payin. |
| `Postgres: Get Payin Variables` | Mengambil `xenithpayEndpoint`, `n8nURL`, dan `homepageURL` dari tabel `variables`. |
| `Aggregate: Payin Variables` | Menggabungkan row variable dari PostgreSQL agar bisa dipetakan dalam satu item. |
| `Code: Map Payin Variables` | Mengubah hasil query variable menjadi object key-value yang mudah dipakai node berikutnya. |
| `Postgres: Check Existing Invoice` | Mengecek apakah `referenceCode` sudah pernah dibuat di tabel `invoices`. |
| `Check: Invoice Reference Available?` | Mengarahkan flow ke proses create invoice jika reference masih kosong, atau ke response duplicate jika sudah ada. |
| `Code: Build Invoice Duplicate Response` | Membuat response `REFERENCE_ALREADY_EXISTS` untuk false branch. |
| `Postgres: Get Payment Channel` | Mengambil mapping `method` dan `channel` dari tabel `payment_channels`. |
| `Code: Build Xenith Payin Requests` | Menyiapkan body request, callback URL, redirect URL, URI signature, dan payload HMAC untuk XenithPay. |
| `Crypto: Create Xenith Payin Signature` | Membuat signature HMAC request payin memakai credential `Xenith-Secret-Key`. |
| `Crypto: Generate Payin Idempotency Key` | Membuat idempotency key agar request payin aman dari retry ganda. |
| `HTTP: Create Xenith Payin` | Mengirim request create payin ke endpoint XenithPay sesuai `xenithpayEndpoint`. |
| `Email: Send Invoice Payment Options` | Mengirim instruksi pembayaran invoice ke email customer. |
| `Postgres: Insert Invoice` | Menyimpan response create payin ke tabel `invoices`. |

Query parameter:

| Parameter | Keterangan |
| --- | --- |
| `customerName` | Nama customer. |
| `email` | Email tujuan invoice; pada template ini juga dipakai sebagai `customerReference`. |
| `initiated_amount` | Nominal pembayaran dalam IDR. |
| `paymentChannel` | Kode channel payin, misalnya `QRIS`, `BRI.VA`, atau `DANA`. |
| `phone_number` | Nomor telepon customer. |
| `referenceCode` | Kode referensi transaksi. |
| `description` | Deskripsi transaksi. |

Contoh:

```text
GET https://<n8n-url>/webhook/create-invoice?customerName=John&email=example@customer.com&initiated_amount=50000&paymentChannel=BRI.VA&phone_number=08123456789&referenceCode=REF-001&description=Pembayaran+Produk
```

Catatan:

- Callback payin dibentuk dari `n8nURL + /webhook/xenith-payin`.
- Redirect status pembayaran dibentuk dari `n8nURL + /webhook/payment?referenceCode=...`.
- `/webhook-test/` dan `/webhook/` hanya mengubah mode trigger n8n, bukan environment XenithPay.

### 2. Simulate Payin

Flow ini hanya untuk sandbox. Gunakan setelah invoice dibuat untuk mensimulasikan hasil pembayaran.

Alur node:

```text
Webhook: Simulate Payin
> Code: Build Simulate Payin Payload
> Crypto: Create Simulate Payin Signature
> HTTP: Simulate Xenith Payin Transaction
```

Penjelasan node:

| Node | Fungsi |
| --- | --- |
| `Webhook: Simulate Payin` | Menerima request GET untuk menjalankan simulator pembayaran payin sandbox. |
| `Code: Build Simulate Payin Payload` | Menyiapkan body simulator, URI signature, dan payload HMAC berdasarkan `payin_id` dan `transaction_status`. |
| `Crypto: Create Simulate Payin Signature` | Membuat signature HMAC simulator memakai credential `Xenith-Secret-Key`. |
| `HTTP: Simulate Xenith Payin Transaction` | Mengirim request ke endpoint simulator sandbox XenithPay. |

Query parameter:

| Parameter | Keterangan |
| --- | --- |
| `payin_id` | Transaction ID dari response create invoice atau email invoice. |
| `transaction_status` | Status simulasi: `SUCCESS`, `FAILED`, atau `EXPIRED`. |

Contoh:

```text
GET https://<n8n-url>/webhook/simulate-payin?payin_id=txn_abc123&transaction_status=SUCCESS
```

Catatan:

- Endpoint simulator hardcoded ke `https://openapi.sandbox.xenithpay.com/v1/simulator/transaction`.
- Flow ini tidak dipakai di XenithPay production.

### 3. Callback Payin

Flow ini menerima callback XenithPay untuk transaksi payin, memvalidasi signature, mengupdate data invoice di database, lalu mengirim email status pembayaran.

Alur node:

```text
Webhook: Xenith Payin Callback
> Code: Build Payin Signature Validation Payload
> Crypto: Create Expected Xenith Payin Signature
> Check: Xenith Payin Signature Valid?
> Postgres: Update Invoice From Callback
> Email: Send Payin Status Notification
```

Output false dari `Check: Xenith Payin Signature Valid?` diarahkan ke `Code: Build Invalid Payin Signature Response`.

Penjelasan node:

| Node | Fungsi |
| --- | --- |
| `Webhook: Xenith Payin Callback` | Menerima callback status payin dari XenithPay. |
| `Code: Build Payin Signature Validation Payload` | Menyiapkan payload validasi signature callback sesuai body yang diterima. |
| `Crypto: Create Expected Xenith Payin Signature` | Membuat expected signature memakai credential `xenith-web-signature-secret`. |
| `Check: Xenith Payin Signature Valid?` | Membandingkan signature dari header XenithPay dengan expected signature. |
| `Code: Build Invalid Payin Signature Response` | Membuat response error untuk callback payin yang signature-nya tidak valid. |
| `Postgres: Update Invoice From Callback` | Mengupdate status dan detail invoice di tabel `invoices`. |
| `Email: Send Payin Status Notification` | Mengirim email notifikasi status payin setelah database berhasil diupdate. |

Webhook path:

| Mode | URL |
| --- | --- |
| Test | `https://<n8n-url>/webhook-test/xenith-payin` |
| Production | `https://<n8n-url>/webhook/xenith-payin` |

Untuk callback XenithPay, selalu gunakan URL production n8n `/webhook/xenith-payin`.

### 4. Payment Status Page

Flow ini menampilkan halaman status pembayaran yang dipakai sebagai redirect setelah customer menyelesaikan flow payin.

Alur node:

```text
Webhook: Payment Status Page
> Wait: Delay Payment Status Lookup
> Postgres: Get Payment Page Variable
> Postgres: Get Invoice For Payment Page
> Postgres: Get Payment Channel For Page
> Respond: Payment Status Page
```

Penjelasan node:

| Node | Fungsi |
| --- | --- |
| `Webhook: Payment Status Page` | Menerima request halaman status pembayaran berdasarkan `referenceCode`. |
| `Wait: Delay Payment Status Lookup` | Memberi jeda singkat agar data callback sempat masuk sebelum halaman membaca status invoice. |
| `Postgres: Get Payment Page Variable` | Mengambil `homepageURL` dari tabel `variables` untuk tombol kembali ke beranda. |
| `Postgres: Get Invoice For Payment Page` | Mengambil data invoice dari tabel `invoices` berdasarkan `referenceCode`. |
| `Postgres: Get Payment Channel For Page` | Mengambil nama channel dari `payment_channels` untuk ditampilkan di halaman status. |
| `Respond: Payment Status Page` | Menghasilkan response HTML halaman status pembayaran. |

Catatan:

- Base URL halaman ini dibentuk dari `n8nURL`.
- Tombol `Kembali ke Beranda` memakai nilai `homepageURL` dari tabel `variables`.

### 5. Create Payout

Flow ini membuat payout/disbursement ke rekening bank atau e-wallet. Variabel workflow diambil dari tabel `variables`, lalu mapping channel diambil dari `payout_channels`.

Alur node:

```text
Webhook: Create Payout
> Postgres: Get Payout Variables
> Aggregate: Payout Variables
> Code: Map Payout Variables
> Postgres: Check Existing Payout
> Check: Payout Reference Available?
> Postgres: Get Payout Channel
> Code: Build Xenith Payout Payload
> Crypto: Create Xenith Payout Signature
> Crypto: Generate Payout Idempotency Key
> HTTP: Create Xenith Payout
> Postgres: Insert Payout
```

Output false dari `Check: Payout Reference Available?` diarahkan ke `Code: Build Payout Duplicate Response`.

Penjelasan node:

| Node | Fungsi |
| --- | --- |
| `Webhook: Create Payout` | Menerima request GET untuk membuat payout/disbursement. |
| `Postgres: Get Payout Variables` | Mengambil `xenithpayEndpoint` dan `n8nURL` dari tabel `variables`. |
| `Aggregate: Payout Variables` | Menggabungkan row variable dari PostgreSQL agar bisa dipetakan dalam satu item. |
| `Code: Map Payout Variables` | Mengubah hasil query variable menjadi object key-value untuk node payout berikutnya. |
| `Postgres: Check Existing Payout` | Mengecek apakah `referenceCode` sudah pernah dibuat di tabel `payouts`. |
| `Check: Payout Reference Available?` | Mengarahkan flow ke proses create payout jika reference masih kosong, atau ke response duplicate jika sudah ada. |
| `Code: Build Payout Duplicate Response` | Membuat response `REFERENCE_ALREADY_EXISTS` untuk false branch. |
| `Postgres: Get Payout Channel` | Mengambil mapping `method` dan `channel` dari tabel `payout_channels`. |
| `Code: Build Xenith Payout Payload` | Menyiapkan body request, callback URL, URI signature, dan payload HMAC untuk XenithPay. |
| `Crypto: Create Xenith Payout Signature` | Membuat signature HMAC request payout memakai credential `Xenith-Secret-Key`. |
| `Crypto: Generate Payout Idempotency Key` | Membuat idempotency key agar request payout aman dari retry ganda. |
| `HTTP: Create Xenith Payout` | Mengirim request create payout ke endpoint XenithPay sesuai `xenithpayEndpoint`. |
| `Postgres: Insert Payout` | Menyimpan response create payout ke tabel `payouts`. |

Query parameter:

| Parameter | Keterangan |
| --- | --- |
| `amount` | Nominal payout dalam IDR. |
| `referenceCode` | Kode referensi unik payout. |
| `payoutChannel` | Kode channel payout, misalnya `CENAIDJA`, `BMRIIDJA`, `DANA`, atau `GOPAY`. |
| `destinationPayoutAccount` | Nomor rekening atau akun tujuan. |
| `destinationPayoutAccountName` | Nama pemilik rekening atau akun tujuan. |
| `email` | Email untuk notifikasi status payout. |

Contoh:

```text
GET https://<n8n-url>/webhook/create-payout?amount=100000&referenceCode=REF-TEST-1&payoutChannel=CENAIDJA&destinationPayoutAccount=555563765328&destinationPayoutAccountName=Andi+Prasetyo&email=example@merchant.com
```

Catatan:

- Callback payout dibentuk dari `n8nURL + /webhook/xenith-payout`.
- `referenceCode` dipakai untuk mengecek data payout yang sudah ada di tabel `payouts`.
- Contoh `CENAIDJA`, `Andi Prasetyo`, dan `555563765328` mengikuti test data sandbox di dokumentasi XenithPay [Simulate Pay Out](https://docs.xenithpay.com/reference/simulate-pay-out). Gunakan data tersebut saat testing sandbox supaya callback payout bisa berjalan.
- Payout production XenithPay baru dapat diproses setelah 1 jam.

### 6. Callback Payout

Flow ini menerima callback XenithPay untuk payout, memvalidasi signature dan status `SUCCESS`, lalu mengupdate data payout di database sebelum mengirim email notifikasi payout berhasil.

Alur node:

```text
Webhook: Xenith Payout Callback
> Code: Build Payout Signature Validation Payload
> Crypto: Create Expected Xenith Payout Signature
> Check: Xenith Payout Signature Valid?
> Postgres: Update Payout From Callback
> Email: Send Payout Success
```

Output false dari `Check: Xenith Payout Signature Valid?` diarahkan ke `Code: Build Invalid Payout Signature Response`.

Penjelasan node:

| Node | Fungsi |
| --- | --- |
| `Webhook: Xenith Payout Callback` | Menerima callback status payout dari XenithPay. |
| `Code: Build Payout Signature Validation Payload` | Menyiapkan payload validasi signature callback sesuai body yang diterima. |
| `Crypto: Create Expected Xenith Payout Signature` | Membuat expected signature memakai credential `xenith-web-signature-secret`. |
| `Check: Xenith Payout Signature Valid?` | Memastikan signature callback valid dan status payout sesuai kondisi success template. |
| `Code: Build Invalid Payout Signature Response` | Membuat response error untuk callback payout yang signature-nya tidak valid atau statusnya bukan `SUCCESS`. |
| `Postgres: Update Payout From Callback` | Mengupdate status dan detail payout di tabel `payouts`. |
| `Email: Send Payout Success` | Mengirim email notifikasi payout berhasil setelah database berhasil diupdate. |

Webhook path:

| Mode | URL |
| --- | --- |
| Test | `https://<n8n-url>/webhook-test/xenith-payout` |
| Production | `https://<n8n-url>/webhook/xenith-payout` |

Untuk callback XenithPay, selalu gunakan URL production n8n `/webhook/xenith-payout`.

## Signature

Request ke XenithPay memakai HMAC-SHA256 dengan format payload:

```text
METHOD
URI
TIMESTAMP
BODY_JSON
```

Hasil signature dikirim dalam format Base64. Secret untuk request API memakai credential `Xenith-Secret-Key`, sedangkan validasi callback memakai `xenith-web-signature-secret`.

## Saat Pindah ke Production

1. Ubah row `xenithpayEndpoint` di tabel `variables` menjadi `https://openapi.xenithpay.com`.
2. Pastikan `n8nURL` sudah memakai domain production publik yang benar.
3. Pastikan `homepageURL` juga sudah mengarah ke domain production front-end Anda.
4. Nonaktifkan flow `Simulate Payin`.
5. Pastikan credential API key, secret request, dan secret callback sudah memakai credential production.

## Catatan Implementasi

- Jangan menyimpan API key atau secret di repository.
- `customerReference` pada template ini memakai email sebagai contoh. Untuk production, ganti sesuai identifier bisnis Anda.
- Public URL harus stabil agar callback dari XenithPay tidak gagal masuk ke n8n.
- Jika XenithPay menambah channel baru, tambahkan row baru ke `xenithpay_database_setup.sql`, lalu jalankan ulang file tersebut.
