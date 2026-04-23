# XenithPay Template — N8N Workflow

Template workflow N8N untuk integrasi **XenithPay Payment Gateway** (sandbox environment). Workflow ini mencakup flow lengkap dari pembuatan invoice, simulasi pembayaran, hingga penanganan callback.

---

## 📋 Daftar Isi

- [Overview](#overview)
- [Prasyarat](#prasyarat)
- [Credentials yang Dibutuhkan](#credentials-yang-dibutuhkan)
- [Workflow Flows](#workflow-flows)
  - [1. Create Invoice (Payin)](#1-create-invoice-payin)
  - [2. Simulate Payin](#2-simulate-payin)
  - [3. Callback Payin](#3-callback-payin)
  - [4. Create Payout](#4-create-payout)
  - [5. Callback Payout](#5-callback-payout)
- [Node Reference](#node-reference)
- [Konfigurasi](#konfigurasi)
- [Cara Penggunaan](#cara-penggunaan)

---

## Overview

Workflow ini terdiri dari **5 flow utama** yang saling terhubung:

```
┌─────────────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│  1. Create Invoice   │────▶│ 2. Simulate Payin │────▶│  3. Callback Payin  │
│     (Payin)          │     │    (Sandbox)       │     │   (Webhook)         │
└─────────────────────┘     └──────────────────┘     └─────────────────────┘

┌─────────────────────┐     ┌─────────────────────┐
│  4. Create Payout    │────▶│  5. Callback Payout │
│     (Disbursement)   │     │   (Webhook)         │
└─────────────────────┘     └─────────────────────┘
```

---

## Prasyarat

| Komponen        | Keterangan                                                       |
| --------------- | ---------------------------------------------------------------- |
| **N8N**         | Self-hosted atau cloud instance (versi **2.16.0** atau lebih baru) |
| **PostgreSQL**  | Database dengan tabel `payment_channels` dan `payout_channels`   |
| **SMTP Server** | Untuk pengiriman email invoice dan notifikasi                    |
| **Ngrok / URL** | Public URL untuk menerima webhook callback dari XenithPay        |
| **XenithPay**   | Akun sandbox di `openapi.sandbox.xenithpay.com`                  |

---

## Credentials yang Dibutuhkan

Sebelum mengimpor workflow, pastikan credential berikut sudah dikonfigurasi di N8N:

| Credential Name                | Tipe              | Kegunaan                                            |
| ------------------------------ | ----------------- | --------------------------------------------------- |
| `Xenith-Api-Key`               | HTTP Header Auth  | API Key untuk autentikasi request ke XenithPay API   |
| `Xenith-Secret-Key`            | Crypto (HMAC)     | Secret key untuk generate HMAC signature request     |
| `xenith-web-signature-secret`  | Crypto (HMAC)     | Secret key untuk validasi signature callback webhook |
| `database` (Postgres)          | PostgreSQL        | Koneksi ke database PostgreSQL                       |
| `SMTP`                         | SMTP              | Konfigurasi email SMTP untuk pengiriman notifikasi   |

---

## Workflow Flows

### 1. Create Invoice (Payin)

Membuat invoice pembayaran baru melalui webhook GET request dan mengirimkan detail ke XenithPay API.

**Alur Node:**

```
Webhook: /webhook/create-invoice (GET)
    │
    ▼
Postgres: Get Payment Channel ─── Ambil method & channel dari DB berdasarkan paymentName
    │
    ▼
Code: Build Xenith Payin Requests ─── Susun body & signature payload
    │
    ▼
Crypto: Create Xenith Payin Signature ─── HMAC-SHA256 sign payload
    │
    ▼
Crypto: Generate Payin Idempotency Key ─── Generate UUID idempotency key
    │
    ▼
HTTP: Create Xenith Payin ─── POST ke /v1/payins
    │
    ▼
Check: Has QRIS Payment Option?
    ├── Ya ──▶ HTTP: Generate QRIS Image ──▶ Email: Send Invoice Payment Options
    └── Tidak ──────────────────────────────▶ Email: Send Invoice Payment Options
```

**Query Parameters (GET):**

| Parameter           | Tipe     | Keterangan                                                    |
| ------------------- | -------- | ------------------------------------------------------------- |
| `customerName`      | String   | Nama customer                                                 |
| `email`             | String   | Email tujuan pengiriman invoice                               |
| `initiated_amount`  | Number   | Nominal pembayaran (IDR)                                      |
| `paymentName`       | String   | Nama metode pembayaran (harus cocok dengan kolom `name` di tabel `payment_channels`) |
| `phone_number`      | String   | Nomor telepon customer                                        |
| `referenceCode`     | String   | Kode referensi unik                                           |
| `description`       | String   | Deskripsi transaksi                                           |

**Contoh Request:**

```
# Test (saat klik 'Listen for test event' di N8N UI)
GET https://<n8n-url>/webhook-test/create-invoice?customerName=John&email=john@example.com&initiated_amount=50000&paymentName=QRIS&phone_number=08123456789&referenceCode=REF-001&description=Pembayaran+Produk

# Production (saat workflow aktif)
GET https://<n8n-url>/webhook/create-invoice?customerName=John&email=john@example.com&initiated_amount=50000&paymentName=QRIS&phone_number=08123456789&referenceCode=REF-001&description=Pembayaran+Produk
```

**Endpoint:** `POST https://openapi.sandbox.xenithpay.com/v1/payins`

> **Catatan tentang `customerReference`:** Pada template ini, query parameter `email` digunakan sebagai nilai `customerReference` di XenithPay API. Ini **hanya contoh implementasi** agar workflow bisa langsung mengirim email notifikasi ke customer. Pada praktiknya, `customerReference` adalah field bebas (free-text) — Anda bisa mengisi ID pelanggan, nomor order, atau identifier apapun sesuai kebutuhan bisnis Anda.

**Output:** Email invoice dikirim ke customer berisi detail pembayaran. Jika metode QRIS, email menyertakan gambar QR Code sebagai attachment.

---

### 2. Simulate Payin

Digunakan khusus di environment **sandbox** untuk mensimulasikan hasil pembayaran. Mendukung 3 status: **SUCCESS**, **FAILED**, dan **EXPIRED**.

**Alur Node:**

```
Webhook: /webhook/simulate-payin (GET)
    │
    ▼
Code: Build Simulate Payin Payload ─── Susun body simulasi (transactionId, status dari query)
    │
    ▼
Crypto: Create Simulate Payin Signature ─── HMAC-SHA256 sign payload
    │
    ▼
HTTP: Simulate Xenith Payin Transaction ─── POST ke /v1/simulator/transaction
```

**Query Parameters (GET):**

| Parameter            | Tipe     | Keterangan                                                  |
| -------------------- | -------- | ----------------------------------------------------------- |
| `payin_id`           | String   | Transaction ID yang didapat dari response Create Invoice     |
| `transaction_status` | String   | Status simulasi: `SUCCESS`, `FAILED`, atau `EXPIRED`         |

**Contoh Request:**

```
# Test
GET https://<n8n-url>/webhook-test/simulate-payin?payin_id=txn_abc123&transaction_status=SUCCESS

# Production
GET https://<n8n-url>/webhook/simulate-payin?payin_id=txn_abc123&transaction_status=SUCCESS
```

**Transaction Status Options:**

| Status    | Keterangan                                                              |
| --------- | ----------------------------------------------------------------------- |
| `SUCCESS` | Pembayaran berhasil diproses                                            |
| `FAILED`  | Pembayaran gagal (misal: saldo tidak cukup, channel error)              |
| `EXPIRED` | Pembayaran melewati batas waktu dan otomatis kedaluwarsa                |

**Endpoint:** `POST https://openapi.sandbox.xenithpay.com/v1/simulator/transaction`

> **Catatan:** Flow ini hanya berfungsi di environment sandbox. Di production, status pembayaran ditentukan oleh payment provider secara real-time.

---

### 3. Callback Payin

Menerima webhook callback dari XenithPay setelah pembayaran diproses. Melakukan validasi signature dan mengirim email notifikasi dengan konten yang disesuaikan berdasarkan status transaksi (`SUCCESS`, `FAILED`, atau `EXPIRED`).

**Alur Node:**

```
Webhook: Xenith Payin Callback ─── POST /webhook/xenith-payin-sandbox
    │
    ▼
Code: Build Signature Validation Payload ─── Extract header signature & build payload
    │
    ▼
Crypto: Create Expected Xenith Signature ─── Generate expected HMAC signature
    │
    ▼
Check: Xenith Signature Valid?
    ├── Valid ──▶ Email: Send Payin Status Notification
    └── Invalid ──▶ (no action)
```

**Webhook Path:** `/webhook/xenith-payin-sandbox` (POST)

**Validasi:**
- Membandingkan `x-xenith-signature` dari header request dengan expected signature yang di-generate menggunakan `xenith-web-signature-secret`
- Jika signature valid → kirim email notifikasi status ke customer

**Email Notifikasi (Status-Aware):**

| Status    | Header Email               | Warna   | Deskripsi                                                |
| --------- | -------------------------- | ------- | -------------------------------------------------------- |
| `SUCCESS` | ✅ Pembayaran Berhasil      | Hijau   | Pembayaran Anda telah berhasil diproses                  |
| `FAILED`  | ❌ Pembayaran Gagal         | Merah   | Pembayaran Anda gagal diproses. Silakan coba lagi        |
| `EXPIRED` | ⏰ Pembayaran Kedaluwarsa   | Kuning  | Pembayaran melewati batas waktu dan dinyatakan kedaluwarsa |

---

### 4. Create Payout

Membuat disbursement/penarikan dana ke rekening bank atau e-wallet customer.

**Alur Node:**

```
Webhook: /webhook/create-payout (GET)
    │
    ▼
Postgres: Get Payout Channel ─── Ambil method & channel dari DB berdasarkan payoutName
    │
    ▼
Code: Build Xenith Payout Payload ─── Susun body & signature payload
    │
    ▼
Crypto: Create Xenith Payout Signature ─── HMAC-SHA256 sign payload
    │
    ▼
Crypto: Generate Payout Idempotency Key ─── Generate UUID idempotency key
    │
    ▼
HTTP: Create Xenith Payout ─── POST ke /v1/payouts
```

**Query Parameters (GET):**

| Parameter                      | Tipe     | Keterangan                                                    |
| ------------------------------ | -------- | ------------------------------------------------------------- |
| `amount`                       | Number   | Nominal penarikan (IDR)                                       |
| `payoutName`                   | String   | Nama metode payout (harus cocok dengan kolom `name` di tabel `payout_channels`) |
| `destinationPayoutAccount`     | String   | Nomor rekening/akun tujuan                                    |
| `destinationPayoutAccountName` | String   | Nama pemilik rekening tujuan                                  |
| `email`                        | String   | Email untuk notifikasi status payout                          |

**Contoh Request:**

```
# Test
GET https://<n8n-url>/webhook-test/create-payout?amount=100000&payoutName=Bank%20Central%20Asia%20(BCA)&destinationPayoutAccount=1234567890&destinationPayoutAccountName=John&email=john@example.com

# Production
GET https://<n8n-url>/webhook/create-payout?amount=100000&payoutName=Bank%20Central%20Asia%20(BCA)&destinationPayoutAccount=1234567890&destinationPayoutAccountName=John&email=john@example.com
```

**Endpoint:** `POST https://openapi.sandbox.xenithpay.com/v1/payouts`

---

### 5. Callback Payout

Menerima webhook callback dari XenithPay setelah payout diproses. Melakukan validasi ganda: signature validity dan transaction status.

**Alur Node:**

```
Webhook: Xenith Payout Callback ─── POST /webhook/xenith-payout-sandbox
    │
    ▼
Code: Build Payout Signature Validation Payload ─── Extract header signature & build payload
    │
    ▼
Crypto: Create Expected Xenith Payout Signature ─── Generate expected HMAC signature
    │
    ▼
Check: Xenith Payout Signature Valid?
    ├── Valid + Status SUCCESS ──▶ Email: Send Payout Success
    └── Invalid / Gagal ──────▶ (no action)
```

**Webhook Path:** `/webhook/xenith-payout-sandbox` (POST)

**Validasi:**
- Signature matching (`x-xenith-signature` vs expected signature)
- Status check (`body.data.status === "SUCCESS"`)
- Jika kedua kondisi terpenuhi → kirim email notifikasi payout berhasil ke customer

---

## Node Reference

### Daftar Lengkap Node

| # | Node Name | Tipe | Flow | Keterangan |
|---|-----------|------|------|------------|
| 1 | `Webhook` | Webhook (GET) | Create Invoice | Menerima request GET dengan query parameters untuk membuat payin baru |
| 2 | `Postgres: Get Payment Channel` | PostgreSQL | Create Invoice | Query tabel `payment_channels` berdasarkan nama metode |
| 3 | `Code: Build Xenith Payin Requests` | Code | Create Invoice | Menyusun request body dan signature payload untuk payin |
| 4 | `Crypto: Create Xenith Payin Signature` | Crypto | Create Invoice | Generate HMAC-SHA256 signature untuk autentikasi request |
| 5 | `Crypto: Generate Payin Idempotency Key` | Crypto | Create Invoice | Generate UUID sebagai idempotency key |
| 6 | `HTTP: Create Xenith Payin` | HTTP Request | Create Invoice | Kirim request pembuatan payin ke XenithPay API |
| 7 | `Check: Has QRIS Payment Option?` | IF | Create Invoice | Cek apakah metode pembayaran adalah QR_CODE |
| 8 | `HTTP: Generate QRIS Image` | HTTP Request | Create Invoice | Generate gambar QR Code dari payment code |
| 9 | `Email: Send Invoice Payment Options` | Email Send | Create Invoice | Kirim email invoice ke customer |
| 10 | `Webhook: Simulate Payin` | Webhook (GET) | Simulate Payin | Menerima request GET dengan payin_id dan transaction_status untuk simulasi |
| 11 | `Code: Build Simulate Payin Payload` | Code | Simulate Payin | Menyusun body simulasi transaksi dengan status yang dipilih |
| 12 | `Crypto: Create Simulate Payin Signature` | Crypto | Simulate Payin | Generate signature untuk request simulasi |
| 13 | `HTTP: Simulate Xenith Payin Transaction` | HTTP Request | Simulate Payin | Kirim request simulasi ke XenithPay sandbox |
| 14 | `Webhook: Xenith Payin Callback` | Webhook | Callback Payin | Menerima callback POST dari XenithPay (payin) |
| 15 | `Code: Build Signature Validation Payload` | Code | Callback Payin | Extract dan susun payload untuk validasi signature |
| 16 | `Crypto: Create Expected Xenith Signature` | Crypto | Callback Payin | Generate expected signature untuk perbandingan |
| 17 | `Check: Xenith Signature Valid?` | IF | Callback Payin | Validasi apakah signature cocok |
| 18 | `Email: Send Payin Status Notification` | Email Send | Callback Payin | Kirim notifikasi status pembayaran (SUCCESS/FAILED/EXPIRED) |
| 19 | `Webhook: Create Payout` | Webhook (GET) | Create Payout | Menerima request GET dengan query parameters untuk membuat payout baru |
| 20 | `Postgres: Get Payout Channel` | PostgreSQL | Create Payout | Query tabel `payout_channels` berdasarkan nama metode |
| 21 | `Code: Build Xenith Payout Payload` | Code | Create Payout | Menyusun request body dan signature payload untuk payout |
| 22 | `Crypto: Create Xenith Payout Signature` | Crypto | Create Payout | Generate HMAC-SHA256 signature untuk request payout |
| 23 | `Crypto: Generate Payout Idempotency Key` | Crypto | Create Payout | Generate UUID sebagai idempotency key |
| 24 | `HTTP: Create Xenith Payout` | HTTP Request | Create Payout | Kirim request pembuatan payout ke XenithPay API |
| 25 | `Webhook: Xenith Payout Callback` | Webhook | Callback Payout | Menerima callback POST dari XenithPay (payout) |
| 26 | `Code: Build Payout Signature Validation Payload` | Code | Callback Payout | Extract dan susun payload untuk validasi signature payout |
| 27 | `Crypto: Create Expected Xenith Payout Signature` | Crypto | Callback Payout | Generate expected signature payout |
| 28 | `Check: Xenith Payout Signature Valid?` | IF | Callback Payout | Validasi signature + status SUCCESS |
| 29 | `Email: Send Payout Success` | Email Send | Callback Payout | Kirim notifikasi payout berhasil |

---

## Konfigurasi

### 1. Callback URL

`callbackUrl` yang dikonfigurasi di node **Code: Build Xenith Payin Requests** dan **Code: Build Xenith Payout Payload** **harus mengarah ke webhook path** yang terdaftar di flow **Callback Payin** dan **Callback Payout**. Ini karena setelah XenithPay memproses transaksi, XenithPay akan mengirimkan notifikasi (callback) ke URL tersebut.

**Hubungan antara `callbackUrl` dan Webhook Node:**

| Flow | Code Node (callbackUrl) | Webhook Node (path) | URL Lengkap |
|------|------------------------|---------------------|-------------|
| **Payin** | `Code: Build Xenith Payin Requests` | `Webhook: Xenith Payin Callback` | `https://<your-public-url>/webhook/xenith-payin-sandbox` |
| **Payout** | `Code: Build Xenith Payout Payload` | `Webhook: Xenith Payout Callback` | `https://<your-public-url>/webhook/xenith-payout-sandbox` |

Update `callbackUrl` di kedua Code node dengan public URL N8N Anda:

```javascript
// Di Code: Build Xenith Payin Requests
// URL ini HARUS cocok dengan path di Webhook: Xenith Payin Callback
callbackUrl: 'https://<your-public-url>/webhook/xenith-payin-sandbox'

// Di Code: Build Xenith Payout Payload
// URL ini HARUS cocok dengan path di Webhook: Xenith Payout Callback
callbackUrl: 'https://<your-public-url>/webhook/xenith-payout-sandbox'
```

**⚠️ Test URL vs Production URL di N8N:**

Setiap Webhook node di N8N memiliki **2 URL** yang bisa dilihat di panel node:

| Tipe | Format Path | Kapan Aktif |
|------|------------|-------------|
| **Test URL** | `/webhook-test/<path>` | Hanya saat klik **"Listen for test event"** di N8N UI |
| **Production URL** | `/webhook/<path>` | Saat workflow **aktif** (toggle ON) |

`callbackUrl` **HARUS menggunakan format Production URL** (`/webhook/`), bukan Test URL (`/webhook-test/`), karena XenithPay mengirim callback secara otomatis saat transaksi diproses — artinya workflow harus sudah aktif dan menggunakan Production URL.

> [!IMPORTANT]
> Jika `callbackUrl` tidak sesuai dengan webhook path, maka callback dari XenithPay tidak akan diterima oleh N8N dan flow Callback Payin / Callback Payout tidak akan berjalan. Pastikan URL publik (ngrok/domain production) aktif dan path-nya sama persis.
>
> Jangan gunakan **Test URL** (`/webhook-test/`) sebagai `callbackUrl` — URL ini hanya aktif sementara saat debugging di N8N UI.

### 2. Database (PostgreSQL)

Workflow ini menggunakan PostgreSQL untuk menyimpan mapping payment channel dan payout channel. Developer perlu melakukan setup berikut:

#### Langkah 1 — Buat Credential PostgreSQL di N8N

1. Buka **Settings > Credentials** di N8N
2. Klik **Add Credential** → pilih **Postgres**
3. Isi konfigurasi koneksi database Anda (host, port, database, user, password)
4. Simpan credential — nama credential ini harus sama dengan yang dipakai di node `Postgres: Get Payment Channel` dan `Postgres: Get Payout Channel`

#### Langkah 2 — Buat Tabel

Jalankan SQL berikut di database PostgreSQL Anda:

```sql
-- Tabel payment_channels (untuk Payin / Create Invoice)
CREATE TABLE IF NOT EXISTS payment_channels (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  method VARCHAR NOT NULL,       -- Metode pembayaran XenithPay (QR_CODE, VIRTUAL_ACCOUNT, EWALLET, dll)
  channel VARCHAR NOT NULL,      -- Kode channel XenithPay (QRIS, BRI.VA, DANA, dll)
  name VARCHAR NOT NULL,         -- Nama metode pembayaran (value untuk query param paymentName)
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Tabel payout_channels (untuk Payout / Disbursement)
CREATE TABLE IF NOT EXISTS payout_channels (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  method VARCHAR NOT NULL,       -- Metode payout XenithPay (BANK_TRANSFER, EWALLET)
  channel VARCHAR NOT NULL,      -- Kode channel XenithPay (CENAIDJA, DANA, dll)
  name VARCHAR NOT NULL,         -- Nama metode payout (value untuk query param payoutName)
  created_at TIMESTAMPTZ DEFAULT now()
);
```

#### Langkah 3 — Seed Data

File SQL untuk mengisi data channel sudah disediakan di repository:

| File | Tabel | Jumlah Channel |
|------|-------|----------------|
| `payment_channels_rows.sql` | `payment_channels` | 14 channel (QRIS, VA, E-Wallet) |
| `payout_channels_rows.sql` | `payout_channels` | 31 channel (Bank Transfer, E-Wallet) |

Jalankan kedua file SQL tersebut ke database Anda:

```bash
psql -h <host> -U <user> -d <database> -f payment_channels_rows.sql
psql -h <host> -U <user> -d <database> -f payout_channels_rows.sql
```

#### Struktur Kolom

**`payment_channels`** — Mapping metode pembayaran (Payin):

| Column     | Tipe          | Keterangan                                              | Contoh               |
| ---------- | ------------- | ------------------------------------------------------- | -------------------- |
| `id`       | UUID          | Primary key                                             | `248d9fd4-...`       |
| `method`   | VARCHAR       | Metode pembayaran XenithPay                              | `QR_CODE`, `VIRTUAL_ACCOUNT`, `EWALLET` |
| `channel`  | VARCHAR       | Kode channel spesifik XenithPay                          | `QRIS`, `BRI.VA`, `DANA` |
| `name`     | VARCHAR       | Nama metode pembayaran (value untuk query param `paymentName`) | `QRIS`, `VA BANK RAKYAT INDONESIA` |
| `created_at` | TIMESTAMPTZ | Waktu pembuatan record                                  | `2026-04-18 07:21:38` |

**`payout_channels`** — Mapping metode payout (Disbursement):

| Column     | Tipe          | Keterangan                                              | Contoh               |
| ---------- | ------------- | ------------------------------------------------------- | -------------------- |
| `id`       | UUID          | Primary key                                             | `8c0b607a-...`       |
| `method`   | VARCHAR       | Metode payout XenithPay                                  | `BANK_TRANSFER`, `EWALLET` |
| `channel`  | VARCHAR       | Kode channel spesifik XenithPay (SWIFT code untuk bank)  | `CENAIDJA`, `DANA`, `GOPAY` |
| `name`     | VARCHAR       | Nama metode payout (value untuk query param `payoutName`)  | `Bank Central Asia (BCA)`, `DANA` |
| `created_at` | TIMESTAMPTZ | Waktu pembuatan record                                  | `2026-04-18 07:21:38` |

> [!NOTE]
> Node `Postgres: Get Payment Channel` dan `Postgres: Get Payout Channel` melakukan query `SELECT` berdasarkan kolom `name` yang cocok dengan query parameter `paymentName` (payin) atau `payoutName` (payout) dari webhook GET request. Pastikan nilai `name` di database sama persis dengan nilai yang dikirim via query parameter.

### 3. Signature Generation

Semua request ke XenithPay API menggunakan HMAC-SHA256 signature dengan format:

```
METHOD\n
URI\n
TIMESTAMP\n
BODY_JSON
```

Signature di-encode dalam **Base64**.

---

## Cara Penggunaan

### Langkah 1 — Import Workflow

1. Buka N8N dashboard
2. Klik **Import Workflow**
3. Upload file `Xenithpay Template.json`

### Langkah 2 — Setup Credentials

1. Buat semua credential sesuai tabel [Credentials yang Dibutuhkan](#credentials-yang-dibutuhkan)
2. Update credential reference di setiap node yang membutuhkan

### Langkah 3 — Setup Database

1. Buat tabel `payment_channels` dan `payout_channels` di PostgreSQL
2. Isi dengan data channel yang tersedia

### Langkah 4 — Setup Callback URL

1. Gunakan **ngrok** atau public URL lain untuk expose N8N
2. Update `callbackUrl` di kedua Code node (Payin & Payout)

### Langkah 5 — Activate Workflow

1. Aktifkan workflow di N8N
2. Akses endpoint melalui:
   - **Create Invoice:** `<n8n-url>/webhook/create-invoice?customerName=...&email=...&initiated_amount=...&paymentName=...&phone_number=...&referenceCode=...&description=...`
   - **Simulate Payin:** `<n8n-url>/webhook/simulate-payin?payin_id=...&transaction_status=SUCCESS`
   - **Create Payout:** `<n8n-url>/webhook/create-payout?amount=...&payoutName=...&destinationPayoutAccount=...&destinationPayoutAccountName=...&email=...`

### Langkah 6 — Testing (Sandbox)

1. Buat invoice melalui webhook GET request ke `/webhook/create-invoice` dengan query parameters yang sesuai
2. Copy Transaction ID dari email invoice
3. Simulasikan pembayaran melalui GET request ke `/webhook/simulate-payin?payin_id=...&transaction_status=SUCCESS` (atau FAILED/EXPIRED)
4. Cek email untuk notifikasi status pembayaran sesuai status yang dipilih

---

## ⚠️ Catatan Penting

- Jangan commit credential/secret key ke version control.
- `redirectUrl` di payin request saat ini mengarah ke `https://www.weselaja.com/` — sesuaikan dengan URL redirect Anda.
- Pastikan ngrok/public URL selalu aktif agar webhook callback bisa diterima.
- `customerReference` pada template ini diisi dengan email customer sebagai contoh agar bisa langsung digunakan untuk pengiriman email. Di implementasi production, Anda bisa mengisi field ini dengan identifier apapun (customer ID, order number, dsb.) dan menangani notifikasi secara terpisah.

### Environment: Sandbox vs Production

Workflow ini dikonfigurasi untuk environment **sandbox**. Untuk beralih ke **production**, sesuaikan URL berikut:

| Komponen | Sandbox | Production |
|----------|---------|------------|
| **API Base URL** | `https://openapi.sandbox.xenithpay.com` | `https://openapi.xenithpay.com` |
| **Payin Endpoint** | `https://openapi.sandbox.xenithpay.com/v1/payins` | `https://openapi.xenithpay.com/v1/payins` |
| **Payout Endpoint** | `https://openapi.sandbox.xenithpay.com/v1/payouts` | `https://openapi.xenithpay.com/v1/payouts` |
| **Simulator** | `https://openapi.sandbox.xenithpay.com/v1/simulator/transaction` | ❌ Tidak tersedia di production |

**Node yang perlu diupdate saat pindah ke production:**

| Node | Yang diganti |
|------|-------------|
| `HTTP: Create Xenith Payin` | URL → `https://openapi.xenithpay.com/v1/payins` |
| `HTTP: Create Xenith Payout` | URL → `https://openapi.xenithpay.com/v1/payouts` |
| `HTTP: Simulate Xenith Payin Transaction` | ⚠️ Hapus/nonaktifkan — simulator hanya untuk sandbox |
| `Code: Build Xenith Payin Requests` | `callbackUrl` → URL production N8N Anda |
| `Code: Build Xenith Payout Payload` | `callbackUrl` → URL production N8N Anda |

> [!WARNING]
> Flow **Simulate Payin** hanya tersedia di environment sandbox. Di production, pembayaran dilakukan langsung oleh customer melalui channel yang dipilih, dan callback dikirim otomatis oleh XenithPay.

---

## 📁 Struktur File

```
Xenithpay-template/
├── Xenithpay Template.json      ← N8N Workflow JSON
├── payment_channels_rows.sql    ← Seed data tabel payment_channels (14 channel)
├── payout_channels_rows.sql     ← Seed data tabel payout_channels (31 channel)
└── README.md                    ← Dokumentasi ini
```

---

## Naming Convention

Semua node mengikuti format penamaan yang konsisten:

| Prefix     | Tipe Node     | Contoh                                  |
| ---------- | ------------- | --------------------------------------- |
| `Webhook:` | Webhook       | `Webhook: Simulate Payin`               |
| `Postgres:`| PostgreSQL    | `Postgres: Get Payment Channel`         |
| `Code:`    | Code (JS)     | `Code: Build Xenith Payin Requests`     |
| `Crypto:`  | Crypto        | `Crypto: Create Xenith Payin Signature` |
| `HTTP:`    | HTTP Request  | `HTTP: Create Xenith Payin`             |
| `Check:`   | IF Condition  | `Check: Has QRIS Payment Option?`       |
| `Email:`   | Email Send    | `Email: Send Invoice Payment Options`   |
| `Note:`    | Sticky Note   | `Note: Create Invoice Flow`             |
