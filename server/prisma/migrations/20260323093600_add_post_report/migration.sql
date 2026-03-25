-- AlterTable
ALTER TABLE "posts" ADD COLUMN     "report_count" INTEGER NOT NULL DEFAULT 0;

-- CreateTable
CREATE TABLE "post_reports" (
    "id" BIGSERIAL NOT NULL,
    "post_id" BIGINT NOT NULL,
    "device_uuid" VARCHAR(36) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "post_reports_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "post_reports_post_id_device_uuid_key" ON "post_reports"("post_id", "device_uuid");

-- AddForeignKey
ALTER TABLE "post_reports" ADD CONSTRAINT "post_reports_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "posts"("id") ON DELETE CASCADE ON UPDATE CASCADE;
