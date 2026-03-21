-- CreateTable
CREATE TABLE "devices" (
    "id" BIGSERIAL NOT NULL,
    "device_uuid" VARCHAR(36) NOT NULL,
    "os" VARCHAR(10) NOT NULL,
    "country" VARCHAR(10) NOT NULL DEFAULT 'KR',
    "app_version" VARCHAR(20),
    "first_seen_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_seen_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "devices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "products" (
    "id" BIGSERIAL NOT NULL,
    "barcode" VARCHAR(20) NOT NULL,
    "name" VARCHAR(500) NOT NULL,
    "brand" VARCHAR(200),
    "category" VARCHAR(100),
    "image_url" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "products_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "scans" (
    "id" BIGSERIAL NOT NULL,
    "device_id" BIGINT NOT NULL,
    "scan_type" VARCHAR(20) NOT NULL DEFAULT 'product',
    "barcode" VARCHAR(20),
    "latitude" DECIMAL(9,6),
    "longitude" DECIMAL(9,6),
    "scanned_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "scans_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "online_prices" (
    "id" BIGSERIAL NOT NULL,
    "scan_id" BIGINT NOT NULL,
    "platform" VARCHAR(30) NOT NULL,
    "price" INTEGER NOT NULL,
    "is_lowest" BOOLEAN NOT NULL DEFAULT false,
    "fetched_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "online_prices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "offline_prices" (
    "id" BIGSERIAL NOT NULL,
    "scan_id" BIGINT NOT NULL,
    "price" INTEGER NOT NULL,
    "store_hint" VARCHAR(200),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "offline_prices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "barcode_contents" (
    "id" BIGSERIAL NOT NULL,
    "scan_id" BIGINT NOT NULL,
    "raw_value" TEXT NOT NULL,
    "content_type" VARCHAR(20) NOT NULL,
    "parsed_data" JSONB,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "barcode_contents_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "devices_device_uuid_key" ON "devices"("device_uuid");

-- CreateIndex
CREATE UNIQUE INDEX "products_barcode_key" ON "products"("barcode");

-- CreateIndex
CREATE UNIQUE INDEX "barcode_contents_scan_id_key" ON "barcode_contents"("scan_id");

-- AddForeignKey
ALTER TABLE "scans" ADD CONSTRAINT "scans_device_id_fkey" FOREIGN KEY ("device_id") REFERENCES "devices"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "online_prices" ADD CONSTRAINT "online_prices_scan_id_fkey" FOREIGN KEY ("scan_id") REFERENCES "scans"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "offline_prices" ADD CONSTRAINT "offline_prices_scan_id_fkey" FOREIGN KEY ("scan_id") REFERENCES "scans"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "barcode_contents" ADD CONSTRAINT "barcode_contents_scan_id_fkey" FOREIGN KEY ("scan_id") REFERENCES "scans"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
