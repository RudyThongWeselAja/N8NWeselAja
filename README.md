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
| **N8N**         | Self-hosted atau cloud instance                                  |
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
| `onlysubs` (Postgres)          | PostgreSQL        | Koneksi ke database PostgreSQL                       |
| `onlysubs` (SMTP)              | SMTP              | Konfigurasi email SMTP untuk pengiriman notifikasi   |

---

## Workflow Flows

### 1. Create Invoice (Payin)

Membuat invoice pembayaran baru melalui form N8N dan mengirimkan detail ke XenithPay API.

**Alur Node:**

```
Form: Create Invoice
    │
    ▼
Postgres: Get Payment Channel ─── Ambil method & channel dari DB
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

**Form Fields:**

| Field               | Tipe     | Keterangan                                                    |
| ------------------- | -------- | ------------------------------------------------------------- |
| Customer Name       | Text     | Nama customer                                                 |
| Customer Email      | Text     | Email tujuan pengiriman invoice                               |
| Jumlah Dana         | Number   | Nominal pembayaran (IDR)                                      |
| Metode Pembayaran   | Dropdown | QRIS, VA Bank Mandiri, VA BRI, DANA                           |
| Nomor Telepon/Hp    | Number   | Nomor telepon customer                                        |
| Reference Code      | Text     | Kode referensi unik                                           |
| Description         | Text     | Deskripsi transaksi                                           |

**Endpoint:** `POST https://openapi.sandbox.xenithpay.com/v1/payins`

**Output:** Email invoice dikirim ke customer berisi detail pembayaran. Jika metode QRIS, email menyertakan gambar QR Code sebagai attachment.

---

### 2. Simulate Payin

Digunakan khusus di environment **sandbox** untuk mensimulasikan hasil pembayaran. Mendukung 3 status: **SUCCESS**, **FAILED**, dan **EXPIRED**.

**Alur Node:**

```
Form: Simulate Payin
    │
    ▼
Code: Build Simulate Payin Payload ─── Susun body simulasi (transactionId, status dari form)
    │
    ▼
Crypto: Create Simulate Payin Signature ─── HMAC-SHA256 sign payload
    │
    ▼
HTTP: Simulate Xenith Payin Transaction ─── POST ke /v1/simulator/transaction
```

**Form Fields:**

| Field                | Tipe     | Keterangan                                                  |
| -------------------- | -------- | ----------------------------------------------------------- |
| Pay In ID            | Text     | Transaction ID yang didapat dari response Create Invoice     |
| Transaction Status   | Dropdown | Status simulasi: `SUCCESS`, `FAILED`, atau `EXPIRED`         |

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
Form: Create Payout
    │
    ▼
Postgres: Get Payout Channel ─── Ambil method & channel dari DB
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

**Form Fields:**

| Field              | Tipe     | Keterangan                                         |
| ------------------ | -------- | -------------------------------------------------- |
| Jumlah Dana        | Number   | Nominal penarikan (IDR)                            |
| Metode Penarikan   | Dropdown | Bank Central Asia (BCA), DANA, LinkAja              |
| Nomor Rekening     | Text     | Nomor rekening/akun tujuan                          |
| Nama pada Rekening | Text     | Nama pemilik rekening tujuan                        |
| Email              | Text     | Email untuk notifikasi status payout                |

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
| 1 | `Form: Create Invoice` | Form Trigger | Create Invoice | Form input untuk membuat payin baru |
| 2 | `Postgres: Get Payment Channel` | PostgreSQL | Create Invoice | Query tabel `payment_channels` berdasarkan nama metode |
| 3 | `Code: Build Xenith Payin Requests` | Code | Create Invoice | Menyusun request body dan signature payload untuk payin |
| 4 | `Crypto: Create Xenith Payin Signature` | Crypto | Create Invoice | Generate HMAC-SHA256 signature untuk autentikasi request |
| 5 | `Crypto: Generate Payin Idempotency Key` | Crypto | Create Invoice | Generate UUID sebagai idempotency key |
| 6 | `HTTP: Create Xenith Payin` | HTTP Request | Create Invoice | Kirim request pembuatan payin ke XenithPay API |
| 7 | `Check: Has QRIS Payment Option?` | IF | Create Invoice | Cek apakah metode pembayaran adalah QR_CODE |
| 8 | `HTTP: Generate QRIS Image` | HTTP Request | Create Invoice | Generate gambar QR Code dari payment code |
| 9 | `Email: Send Invoice Payment Options` | Email Send | Create Invoice | Kirim email invoice ke customer |
| 10 | `Form: Simulate Payin` | Form Trigger | Simulate Payin | Form input Payin ID dan Transaction Status untuk simulasi |
| 11 | `Code: Build Simulate Payin Payload` | Code | Simulate Payin | Menyusun body simulasi transaksi dengan status yang dipilih |
| 12 | `Crypto: Create Simulate Payin Signature` | Crypto | Simulate Payin | Generate signature untuk request simulasi |
| 13 | `HTTP: Simulate Xenith Payin Transaction` | HTTP Request | Simulate Payin | Kirim request simulasi ke XenithPay sandbox |
| 14 | `Webhook: Xenith Payin Callback` | Webhook | Callback Payin | Menerima callback POST dari XenithPay (payin) |
| 15 | `Code: Build Signature Validation Payload` | Code | Callback Payin | Extract dan susun payload untuk validasi signature |
| 16 | `Crypto: Create Expected Xenith Signature` | Crypto | Callback Payin | Generate expected signature untuk perbandingan |
| 17 | `Check: Xenith Signature Valid?` | IF | Callback Payin | Validasi apakah signature cocok |
| 18 | `Email: Send Payin Status Notification` | Email Send | Callback Payin | Kirim notifikasi status pembayaran (SUCCESS/FAILED/EXPIRED) |
| 19 | `Form: Create Payout` | Form Trigger | Create Payout | Form input untuk membuat payout baru |
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

Update `callbackUrl` di node `Code: Build Xenith Payin Requests` dan `Code: Build Xenith Payout Payload` dengan public URL N8N Anda:

```javascript
// Ganti URL ini dengan public URL N8N Anda
callbackUrl: 'https://<your-public-url>/webhook/xenith-payin-sandbox'
```

### 2. Database Tables

Pastikan tabel berikut tersedia di database PostgreSQL:

**`payment_channels`** — Mapping nama metode pembayaran ke XenithPay channel code:

| Column   | Contoh Value            |
| -------- | ----------------------- |
| `name`   | `QRIS`                  |
| `method` | `QR_CODE`               |
| `channel`| `QRIS`                  |

**`payout_channels`** — Mapping nama metode payout ke XenithPay channel code:

| Column   | Contoh Value               |
| -------- | -------------------------- |
| `name`   | `Bank Central Asia (BCA)`  |
| `method` | `BANK_TRANSFER`            |
| `channel`| `BCA`                      |

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
2. Akses form melalui:
   - **Create Invoice:** `<n8n-url>/form/create-payin`
   - **Simulate Payin:** `<n8n-url>/form/simulate-payin`
   - **Create Payout:** `<n8n-url>/form/create-payout`

### Langkah 6 — Testing (Sandbox)

1. Buat invoice melalui form Create Invoice
2. Copy Transaction ID dari email invoice
3. Simulasikan pembayaran melalui form Simulate Payin (pilih status: SUCCESS, FAILED, atau EXPIRED)
4. Cek email untuk notifikasi status pembayaran sesuai status yang dipilih

---

## ⚠️ Catatan Penting

- Workflow ini dikonfigurasi untuk environment **sandbox** (`openapi.sandbox.xenithpay.com`). Untuk production, ganti base URL API ke endpoint production.
- Jangan commit credential/secret key ke version control.
- `redirectUrl` di payin request saat ini mengarah ke `https://www.weselaja.com/` — sesuaikan dengan URL redirect Anda.
- Pastikan ngrok/public URL selalu aktif agar webhook callback bisa diterima.

---

## 📁 Struktur File

```
Xenithpay-template/
├── Xenithpay Template.json   ← N8N Workflow JSON
└── README.md                 ← Dokumentasi ini
```

---

## Naming Convention

Semua node mengikuti format penamaan yang konsisten:

| Prefix     | Tipe Node     | Contoh                                  |
| ---------- | ------------- | --------------------------------------- |
| `Form:`    | Form Trigger  | `Form: Create Invoice`                  |
| `Postgres:`| PostgreSQL    | `Postgres: Get Payment Channel`         |
| `Code:`    | Code (JS)     | `Code: Build Xenith Payin Requests`     |
| `Crypto:`  | Crypto        | `Crypto: Create Xenith Payin Signature` |
| `HTTP:`    | HTTP Request  | `HTTP: Create Xenith Payin`             |
| `Check:`   | IF Condition  | `Check: Has QRIS Payment Option?`       |
| `Email:`   | Email Send    | `Email: Send Invoice Payment Options`   |
| `Webhook:` | Webhook       | `Webhook: Xenith Payin Callback`        |
| `Note:`    | Sticky Note   | `Note: Create Invoice Flow`             |
