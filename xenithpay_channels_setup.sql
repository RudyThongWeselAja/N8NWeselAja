-- XenithPay channel setup for the n8n workflow.
-- Run this file once during setup, or rerun it safely when you need to refresh
-- the bundled channel seed data.

BEGIN;

CREATE TABLE IF NOT EXISTS public.payment_channels (
  method VARCHAR(64) NOT NULL,
  channel VARCHAR(64) NOT NULL,
  name VARCHAR(160) NOT NULL
);

CREATE TABLE IF NOT EXISTS public.payout_channels (
  method VARCHAR(64) NOT NULL,
  channel VARCHAR(64) NOT NULL,
  name VARCHAR(160) NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_payment_channels_channel
  ON public.payment_channels (channel);

CREATE UNIQUE INDEX IF NOT EXISTS ux_payout_channels_channel
  ON public.payout_channels (channel);

INSERT INTO public.payment_channels (method, channel, name) VALUES
  ('QR_CODE', 'QRIS', 'QRIS'),
  ('VIRTUAL_ACCOUNT', 'BMI.VA', 'VA MAYBANK INDONESIA'),
  ('VIRTUAL_ACCOUNT', 'MDR.VA', 'VA BANK MANDIRI'),
  ('VIRTUAL_ACCOUNT', 'BDMN.VA', 'VA BANK DANAMON'),
  ('EWALLET', 'DANA', 'DANA'),
  ('EWALLET_PUSH_NOTIF', 'OVO', 'OVO'),
  ('VIRTUAL_ACCOUNT', 'INTERBANK_BCA.VA', 'VA BANK CENTRAL ASIA (INTERBANK)'),
  ('VIRTUAL_ACCOUNT', 'BRI.VA', 'VA BANK RAKYAT INDONESIA'),
  ('VIRTUAL_ACCOUNT', 'PTB.VA', 'VA BANK PERMATA'),
  ('VIRTUAL_ACCOUNT', 'BNI.VA', 'VA BANK NEGARA INDONESIA'),
  ('VIRTUAL_ACCOUNT', 'CIMBN.VA', 'VA CIMB NIAGA'),
  ('VIRTUAL_ACCOUNT', 'INA.VA', 'VA BANK INA PERDANA'),
  ('VIRTUAL_ACCOUNT', 'BAG.VA', 'VA BANK ARTHA GRAHA'),
  ('VIRTUAL_ACCOUNT', 'BSS.VA', 'VA BANK SAHABAT SAMPOERNA')
ON CONFLICT (channel) DO UPDATE SET
  method = EXCLUDED.method,
  name = EXCLUDED.name;

INSERT INTO public.payout_channels (method, channel, name) VALUES
  ('EWALLET', 'SHOPEEPAY', 'ShopeePay'),
  ('BANK_TRANSFER', 'SSPIIDJA', 'Bank SeaBank Indonesia'),
  ('BANK_TRANSFER', 'BRINIDJA', 'Bank BRI'),
  ('BANK_TRANSFER', 'HSBCIDJA', 'Bank HSBC Indonesia'),
  ('BANK_TRANSFER', 'PDYKIDJ1', 'Bank BPD DIY'),
  ('BANK_TRANSFER', 'BSMDIDJA', 'Bank BSI (Bank Syariah Indonesia)'),
  ('BANK_TRANSFER', 'SCBLIDJX', 'Bank Standard Chartered'),
  ('BANK_TRANSFER', 'CITIIDJX', 'Citibank'),
  ('BANK_TRANSFER', 'MUABIDJA', 'Bank Muamalat Indonesia'),
  ('BANK_TRANSFER', 'BNINIDJA', 'Bank Negara Indonesia (BNI)'),
  ('BANK_TRANSFER', 'PDJGIDJ1', 'Bank Jateng'),
  ('BANK_TRANSFER', 'BBBAIDJA', 'Bank Permata'),
  ('BANK_TRANSFER', 'ABALIDBS', 'BPD Bali'),
  ('EWALLET', 'GOPAY', 'GoPay'),
  ('BANK_TRANSFER', 'ATOSIDJ1', 'Bank Jago'),
  ('EWALLET', 'LINKAJA', 'LinkAja'),
  ('BANK_TRANSFER', 'PINBIDJA', 'Bank Panin'),
  ('BANK_TRANSFER', 'BMRIIDJA', 'Bank Mandiri'),
  ('BANK_TRANSFER', 'IBBKIDJA', 'Bank Maybank'),
  ('BANK_TRANSFER', 'BBLUIDJA', 'Bank Digital BCA'),
  ('BANK_TRANSFER', 'CENAIDJA', 'Bank Central Asia (BCA)'),
  ('EWALLET', 'OVO', 'OVO'),
  ('EWALLET', 'DANA', 'DANA'),
  ('BANK_TRANSFER', 'PDJTIDJ1', 'Bank Jatim'),
  ('BANK_TRANSFER', 'YUDBIDJ1', 'Bank Neo Commerce'),
  ('BANK_TRANSFER', 'PDJBIDJA', 'BPD Jawa Barat dan Banten'),
  ('BANK_TRANSFER', 'BNIAIDJA', 'Bank CIMB Niaga'),
  ('BANK_TRANSFER', 'MEGAIDJA', 'Bank Mega'),
  ('BANK_TRANSFER', 'DBSBIDJA', 'Bank DBS Indonesia'),
  ('BANK_TRANSFER', 'NISPIDJA', 'Bank OCBC NISP'),
  ('BANK_TRANSFER', 'BDINIDJA', 'Bank Danamon')
ON CONFLICT (channel) DO UPDATE SET
  method = EXCLUDED.method,
  name = EXCLUDED.name;

COMMIT;
