-- CreateTable
CREATE TABLE "device_favorites" (
    "id" BIGSERIAL NOT NULL,
    "device_uuid" VARCHAR(36) NOT NULL,
    "barcode" VARCHAR(20) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "device_favorites_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "device_favorites_device_uuid_barcode_key" ON "device_favorites"("device_uuid", "barcode");
