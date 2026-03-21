import axios from 'axios';

export interface OpenFoodFactsResult {
  productName: string;
  brand: string | null;
  imageUrl: string | null;
}

export async function searchOpenFoodFacts(barcode: string): Promise<OpenFoodFactsResult | null> {
  try {
    const response = await axios.get(
      `https://world.openfoodfacts.org/api/v2/product/${barcode}`,
      { timeout: 5000 }
    );

    if (response.data.status !== 1 || !response.data.product) return null;

    const product = response.data.product;
    const productName = product.product_name_ko || product.product_name || '';
    if (!productName) return null;

    return {
      productName,
      brand: product.brands || null,
      imageUrl: product.image_url || null,
    };
  } catch {
    return null;
  }
}
