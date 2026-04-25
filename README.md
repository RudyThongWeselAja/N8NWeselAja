# XenithPay n8n Workflow Template

Template ini berisi workflow n8n untuk integrasi XenithPay di environment sandbox. Di dalamnya sudah ada flow untuk membuat invoice payin, simulasi pembayaran sandbox, menerima callback payin, membuat payout, dan menerima callback payout.

Dokumentasi ini sudah memakai setup database terpadu: schema tabel dan seed data channel berada dalam satu file SQL, yaitu `xenithpay_channels_setup.sql`.

## Isi Paket

| File | Keterangan |
| --- | --- |
| `Xenithpay Template.json` | Workflow n8n yang di-import ke instance n8n. |
| `xenithpay_channels_setup.sql` | Satu file SQL untuk membuat tabel `payment_channels` dan `payout_channels`, sekaligus mengisi seed channel. |
| `README.md` | Panduan setup dan penggunaan workflow. |

Tidak ada file seed terpisah yang perlu dijalankan. Semua kebutuhan database channel sekarang ada di `xenithpay_channels_setup.sql`.

## Prasyarat

| Komponen | Keterangan |
| --- | --- |
| n8n | Self-hosted atau cloud instance yang mendukung workflow JSON ini. |
| Community node | Install `n8n-nodes-globals` lewat Settings > Community Nodes. |
| PostgreSQL | Dipakai untuk mapping channel payin dan payout. |
| SMTP | Dipakai untuk email invoice dan notifikasi transaksi. |
| Public URL | Domain publik atau ngrok agar webhook callback XenithPay bisa masuk ke n8n. |
| XenithPay sandbox | API sandbox memakai `https://openapi.sandbox.xenithpay.com`. |

## Setup Cepat

1. Import `Xenithpay Template.json` ke n8n.
2. Buat credential yang dibutuhkan: API key XenithPay, secret HMAC, global variables, PostgreSQL, dan SMTP.
3. Jalankan file database terpadu:

```bash
psql -h <host> -U <user> -d <database> -f xenithpay_channels_setup.sql
```

4. Isi global variables dengan endpoint dan callback URL public.
5. Aktifkan workflow, lalu panggil webhook `create-invoice`, `simulate-payin`, atau `create-payout` sesuai kebutuhan.

## Credentials n8n

| Credential | Tipe | Dipakai untuk |
| --- | --- | --- |
| `Xenith-Api-Key` | HTTP Header Auth | Header autentikasi request ke XenithPay. |
| `Xenith-Secret-Key` | Crypto HMAC | Signature request payin, payout, dan simulator. |
| `xenith-web-signature-secret` | Crypto HMAC | Validasi signature callback dari XenithPay. |
| `WeselAja Global Variables` | Global Constants Api | Menyimpan endpoint dan callback URL. |
| `database` | PostgreSQL | Query channel dari tabel `payment_channels` dan `payout_channels`. |
| `SMTP` | SMTP | Mengirim invoice dan notifikasi email. |

Nama credential di atas mengikuti nama yang dipakai di workflow. Jika nama credential di n8n berbeda, pilih ulang credential pada node terkait setelah import.

## Global Variables

Workflow memakai community node `n8n-nodes-globals`, jadi endpoint dan callback URL cukup diatur satu kali di credential `WeselAja Global Variables`.

Set format credential ke `Key-value pairs`, lalu isi:

```text
xenithpayEndpoint=https://openapi.sandbox.xenithpay.com
callbackUrlPayin=https://<your-public-url>/webhook/xenith-payin
callbackUrlPayout=https://<your-public-url>/webhook/xenith-payout
redirectUrl=https://www.weselaja.com/
```

Keterangan:

| Key | Keterangan |
| --- | --- |
| `xenithpayEndpoint` | Base URL XenithPay. Untuk sandbox gunakan `https://openapi.sandbox.xenithpay.com`; untuk production gunakan `https://openapi.xenithpay.com`. |
| `callbackUrlPayin` | URL callback payin yang mengarah ke webhook production `/webhook/xenith-payin`. |
| `callbackUrlPayout` | URL callback payout yang mengarah ke webhook production `/webhook/xenith-payout`. |
| `redirectUrl` | URL tujuan setelah customer menyelesaikan pembayaran. |

Gunakan path `/webhook/`, bukan `/webhook-test/`, untuk `callbackUrlPayin` dan `callbackUrlPayout`. XenithPay mengirim callback ketika workflow aktif, sehingga callback harus mengarah ke production webhook n8n.

## Database

Workflow membutuhkan dua tabel lookup:

| Tabel | Dipakai oleh | Isi |
| --- | --- | --- |
| `payment_channels` | Create Invoice / Payin | 14 channel payin: QRIS, virtual account, dan e-wallet. |
| `payout_channels` | Create Payout | 31 channel payout: bank transfer dan e-wallet. |

Semua schema dan seed ada di satu file:

```bash
psql -h <host> -U <user> -d <database> -f xenithpay_channels_setup.sql
```

File tersebut melakukan:

- `CREATE TABLE IF NOT EXISTS public.payment_channels`
- `CREATE TABLE IF NOT EXISTS public.payout_channels`
- Membuat index lookup pada kolom `channel`
- Insert seed channel payin dan payout
- `ON CONFLICT (id) DO UPDATE` agar aman dijalankan ulang

Struktur kolom kedua tabel sama:

| Kolom | Tipe | Keterangan |
| --- | --- | --- |
| `id` | UUID | Primary key data channel. |
| `method` | VARCHAR(64) | Metode XenithPay, misalnya `QR_CODE`, `VIRTUAL_ACCOUNT`, `BANK_TRANSFER`, atau `EWALLET`. |
| `channel` | VARCHAR(64) | Kode channel yang dikirim dari query parameter webhook. |
| `name` | VARCHAR(160) | Nama channel untuk dibaca manusia. |
| `created_at` | TIMESTAMPTZ | Timestamp seed channel. |

Node PostgreSQL melakukan lookup berdasarkan kolom `channel`:

- `paymentChannel` pada webhook `create-invoice` dicocokkan ke `payment_channels.channel`
- `payoutChannel` pada webhook `create-payout` dicocokkan ke `payout_channels.channel`

Pastikan nilai query parameter sama persis dengan kode channel di database, misalnya `BRI.VA`, `QRIS`, `CENAIDJA`, atau `DANA`.

## Flow Workflow

### 1. Create Invoice / Payin

Membuat invoice pembayaran baru dari webhook GET, mengambil mapping channel dari PostgreSQL, membuat signature HMAC, mengirim request ke XenithPay, lalu mengirim email invoice ke customer.

Alur node:

```text
Webhook: Create Invoice
> Globals: Get Payin Constants
> Postgres: Get Payment Channel
> Code: Build Xenith Payin Requests
> Crypto: Create Xenith Payin Signature
> Crypto: Generate Payin Idempotency Key
> HTTP: Create Xenith Payin
> Email: Send Invoice Payment Options
```

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

### 2. Simulate Payin

Flow ini hanya untuk sandbox. Gunakan untuk mensimulasikan hasil pembayaran setelah invoice dibuat.

Alur node:

```text
Webhook: Simulate Payin
> Code: Build Simulate Payin Payload
> Crypto: Create Simulate Payin Signature
> HTTP: Simulate Xenith Payin Transaction
```

Query parameter:

| Parameter | Keterangan |
| --- | --- |
| `payin_id` | Transaction ID dari response create invoice atau email invoice. |
| `transaction_status` | Status simulasi: `SUCCESS`, `FAILED`, atau `EXPIRED`. |

Contoh:

```text
GET https://<n8n-url>/webhook/simulate-payin?payin_id=txn_abc123&transaction_status=SUCCESS
```

Endpoint simulator memakai URL sandbox hardcoded:

```text
https://openapi.sandbox.xenithpay.com/v1/simulator/transaction
```

Nonaktifkan atau hapus flow simulator saat workflow dipakai untuk production.

### 3. Callback Payin

Menerima callback XenithPay untuk transaksi payin, memvalidasi signature, lalu mengirim email status pembayaran.

Alur node:

```text
Webhook: Xenith Payin Callback
> Code: Build Signature Validation Payload
> Crypto: Create Expected Xenith Signature
> Check: Xenith Signature Valid?
> Email: Send Payin Status Notification
```

Webhook path:

| Mode | URL |
| --- | --- |
| Test | `https://<n8n-url>/webhook-test/xenith-payin` |
| Production | `https://<n8n-url>/webhook/xenith-payin` |

Status email yang didukung: `SUCCESS`, `FAILED`, dan `EXPIRED`.

### 4. Create Payout

Membuat payout/disbursement ke rekening bank atau e-wallet. Mapping channel payout diambil dari tabel `payout_channels`.

Alur node:

```text
Webhook: Create Payout
> Globals: Get Payout Constants
> Postgres: Get Payout Channel
> Code: Build Xenith Payout Payload
> Crypto: Create Xenith Payout Signature
> Crypto: Generate Payout Idempotency Key
> HTTP: Create Xenith Payout
```

Query parameter:

| Parameter | Keterangan |
| --- | --- |
| `amount` | Nominal payout dalam IDR. |
| `payoutChannel` | Kode channel payout, misalnya `CENAIDJA`, `BMRIIDJA`, `DANA`, atau `GOPAY`. |
| `destinationPayoutAccount` | Nomor rekening atau akun tujuan. |
| `destinationPayoutAccountName` | Nama pemilik rekening atau akun tujuan. |
| `email` | Email untuk notifikasi status payout. |

Contoh:

```text
GET https://<n8n-url>/webhook/create-payout?amount=100000&payoutChannel=CENAIDJA&destinationPayoutAccount=555563765328&destinationPayoutAccountName=Andi+Prasetyo&email=example@merchant.com
```

Catatan production: transaksi payout di XenithPay production baru dapat diproses setelah 1 jam.

### 5. Callback Payout

Menerima callback XenithPay untuk payout, memvalidasi signature, mengecek status `SUCCESS`, lalu mengirim email notifikasi payout berhasil.

Alur node:

```text
Webhook: Xenith Payout Callback
> Code: Build Payout Signature Validation Payload
> Crypto: Create Expected Xenith Payout Signature
> Check: Xenith Payout Signature Valid?
> Email: Send Payout Success
```

Webhook path:

| Mode | URL |
| --- | --- |
| Test | `https://<n8n-url>/webhook-test/xenith-payout` |
| Production | `https://<n8n-url>/webhook/xenith-payout` |

## Signature

Request ke XenithPay memakai HMAC-SHA256 dengan format payload:

```text
METHOD
URI
TIMESTAMP
BODY_JSON
```

Hasil signature dikirim dalam format Base64. Secret untuk request API memakai credential `Xenith-Secret-Key`, sedangkan validasi callback memakai `xenith-web-signature-secret`.

## Sandbox dan Production

| Komponen | Sandbox | Production |
| --- | --- | --- |
| Base URL | `https://openapi.sandbox.xenithpay.com` | `https://openapi.xenithpay.com` |
| Payin | `/v1/payins` | `/v1/payins` |
| Payout | `/v1/payouts` | `/v1/payouts` |
| Simulator | `/v1/simulator/transaction` | Tidak tersedia |

Saat pindah ke production:

1. Ubah `xenithpayEndpoint` di Global Variables ke `https://openapi.xenithpay.com`.
2. Pastikan `callbackUrlPayin` dan `callbackUrlPayout` memakai domain production yang aktif.
3. Nonaktifkan flow `Simulate Payin`.
4. Pastikan credential API key, secret request, dan secret callback sudah memakai credential production.

## Catatan Implementasi

- Jangan menyimpan API key atau secret di repository.
- `customerReference` pada template ini memakai email agar notifikasi bisa langsung dikirim. Untuk production, ganti sesuai identifier bisnis Anda, misalnya customer ID atau order ID.
- `redirectUrl` masih contoh dan perlu disesuaikan dengan web front-end Anda.
- Public URL harus stabil agar callback dari XenithPay tidak gagal masuk ke n8n.
- Jika channel baru ditambahkan oleh XenithPay, tambahkan row baru ke `xenithpay_channels_setup.sql`, lalu jalankan ulang file tersebut.
