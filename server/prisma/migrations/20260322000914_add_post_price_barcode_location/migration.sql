/*
  Warnings:

  - Added the required column `price` to the `posts` table without a default value. This is not possible if the table is not empty.

*/
-- AlterTable
ALTER TABLE "posts" ADD COLUMN     "barcode" VARCHAR(20),
ADD COLUMN     "latitude" DECIMAL(9,6),
ADD COLUMN     "longitude" DECIMAL(9,6),
ADD COLUMN     "price" INTEGER NOT NULL,
ADD COLUMN     "share_location" BOOLEAN NOT NULL DEFAULT false;
