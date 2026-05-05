# XenithPay n8n Workflow Template

Template n8n ini menyediakan integrasi lengkap dengan **XenithPay** untuk memproses *Pay-In* (penerimaan pembayaran dari customer) dan *Pay-Out* (pencairan dana ke merchant). Template ini sudah siap digunakan untuk mode *Sandbox* dan didesain agar sangat mudah dipindahkan ke environment *Production*.

---

## 📋 Prasyarat

Sebelum memulai, pastikan Anda memiliki:
1. **n8n (Fresh Install / Instance Baru)**: Disarankan menggunakan instance n8n yang baru (belum ada project dan *credential* sebelumnya). Hal ini karena saat Anda meng-import template, n8n akan secara otomatis mengenali dan mempermudah pemetaan *Credentials* ke semua node, sehingga Anda tidak perlu melakukan setup manual satu per satu pada setiap *node*.
2. **PostgreSQL**: Database untuk menyimpan riwayat transaksi, referensi channel, dan variabel environment workflow.
3. **SMTP**: Konfigurasi email aktif untuk mengirim notifikasi dan invoice.
4. **Akun XenithPay**: *Credential* API Key dan Secret (untuk Sandbox atau Production).
5. **Public URL**: Domain publik untuk instance n8n Anda (bisa menggunakan `ngrok` untuk lokal) agar bisa menerima *Callback/Webhook* dari sistem XenithPay.

---

## 🚀 Setup Cepat

Ikuti langkah-langkah ini untuk menjalankan template:

### 1. Setup Database
Jalankan script SQL yang telah disediakan untuk membuat struktur tabel dan mengisi data channel default.
```bash
psql -h <host> -p 5432 -U <user> -d <database> -f xenithpay_database_setup.sql
```
*(Atau cukup copy-paste isi `xenithpay_database_setup.sql` dan jalankan di Query Editor PostgreSQL Anda).*

### 2. Konfigurasi Variabel
Perbarui tabel `variables` di database Anda dengan URL environment yang sesuai:
```sql
UPDATE public.variables
SET value = CASE key
  WHEN 'xenithpayEndpoint' THEN 'https://openapi.sandbox.xenithpay.com' -- Gunakan Sandbox API untuk testing
  WHEN 'n8nURL' THEN 'https://domain-n8n-anda.com' -- Base URL n8n Anda (tanpa garis miring / di akhir)
  WHEN 'homepageURL' THEN 'https://domain-website-anda.com' -- URL untuk tombol 'Kembali ke Beranda'
END
WHERE key IN ('xenithpayEndpoint', 'n8nURL', 'homepageURL');
```

### 3. Import Workflow di n8n
1. Buka n8n dan buat *Workflow* baru.
2. Import file `Xenithpay Template.json`.
3. Buat dan sambungkan *Credentials* berikut pada node yang membutuhkannya:

   *(Penting: Pastikan Anda memberi nama Credential persis seperti daftar di bawah ini agar otomatis terhubung. Lihat contoh gambar di bawah untuk posisi penamaan)*
   
   ![Contoh Penamaan Credential](images/credential-example.png)
   - `Xenith-Api-Key`: *Credential* *HTTP Header Auth* (Header autentikasi API XenithPay).
   - `Xenith-Secret-Key`: *Credential* *Crypto HMAC* (Untuk memverifikasi signature Pay-In & Pay-Out).
   - `xenith-web-signature-secret`: *Credential* *Crypto HMAC* (Untuk memverifikasi validitas Callback dari XenithPay).
   - `database`: *Credential* *PostgreSQL* untuk menyambung ke database Anda.
   - `SMTP`: *Credential* *SMTP* untuk mengirim email.

### 4. Publish Workflow
Aktifkan workflow dengan mengklik tombol **Publish** di pojok kanan atas n8n.
**Penting:** Selalu gunakan URL webhook utama (`/webhook/...`), bukan test URL (`/webhook-test/...`) saat menerima callback otomatis dari XenithPay.

---

## 🗂 Struktur Tabel Database

Script database akan secara otomatis membuat 5 tabel ini:
- `variables`: Menyimpan konfigurasi URL secara dinamis (XenithPay Endpoint, n8n URL, Homepage URL).
- `invoices`: Menyimpan riwayat tagihan transaksi *Pay-In*.
- `payouts`: Menyimpan riwayat transaksi pencairan *Pay-Out*.
- `payment_channels`: Daftar metode pembayaran *Pay-In* yang didukung (QRIS, VA, E-Wallet).
- `payout_channels`: Daftar metode pencairan *Pay-Out* yang didukung (Bank, E-Wallet).

---

## 🔄 Alur Integrasi (Webhook Endpoints)

Anda bisa memicu workflow dengan melakukan pemanggilan HTTP GET ke endpoint n8n berikut:

### 1. Pay-In (Menerima Pembayaran)
* **Create Invoice**: `GET <n8nURL>/webhook/create-invoice`
  *Membuat tagihan pembayaran, menyimpan ke database, dan mengirimkan email tagihan ke customer.*
  > Parameter wajib: `customerName`, `email`, `initiated_amount`, `paymentChannel`, `phone_number`, `referenceCode`, `description`

* **Simulate Pay-In (Sandbox Only)**: `GET <n8nURL>/webhook/simulate-payin`
  *Mensimulasikan pembayaran berhasil/gagal (Hanya berfungsi di Sandbox).*
  > Parameter wajib: `payin_id`, `transaction_status` (Isi dengan SUCCESS/FAILED/EXPIRED)

* **Callback Pay-In**: Endpoint `<n8nURL>/webhook/xenith-payin` (Otomatis dipanggil oleh XenithPay saat status pembayaran berubah).
* **Payment Status Page**: Endpoint UI untuk menampilkan status tagihan kepada user.

### 2. Pay-Out (Mencairkan Dana)
* **Create Payout**: `GET <n8nURL>/webhook/create-payout`
  *Membuat permintaan pencairan dana ke rekening bank atau e-wallet tujuan.*
  > Parameter wajib: `amount`, `referenceCode`, `payoutChannel`, `destinationPayoutAccount`, `destinationPayoutAccountName`, `email`

* **Callback Pay-Out**: Endpoint `<n8nURL>/webhook/xenith-payout` (Otomatis dipanggil oleh XenithPay saat dana berhasil dicairkan).

---

## 🌍 Pindah ke Production (Go-Live)

Jika Anda sudah selesai melakukan pengujian di *Sandbox* dan siap beralih ke *Production*:

1. Ubah nilai `xenithpayEndpoint` di tabel `variables` database menjadi: `https://openapi.xenithpay.com`.
2. Pastikan nilai `n8nURL` menggunakan domain n8n publik Anda yang valid.
3. Update semua *Credentials* (API Key, Secret Key, Webhook Signature Secret) di n8n dengan *Production Keys* yang didapat dari Dashboard XenithPay Anda.
4. Anda bisa mengabaikan endpoint `Simulate Payin` karena fungsi ini tidak tersedia di environment Production.

---

## 💡 Best Practices & Keamanan
- Pastikan `referenceCode` pada tagihan (*Invoice*) maupun *Payout* bersifat unik. Sistem akan menolak jika mendeteksi ID duplikat.
- Jangan pernah melakukan *commit* atau menyimpan *Credential* API di dalam kode source (selalu manfaatkan fitur *Credentials* milik n8n).
- Pada saat production, pastikan koneksi PostgreSQL Anda terlindungi dengan aturan *firewall* yang baik.
