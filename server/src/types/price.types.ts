export interface PriceEntry {
  platform: string;
  price: number;
  url: string;
  is_lowest: boolean;
}

export interface PriceResponse {
  barcode: string;
  product_name: string;
  image_url: string | null;
  prices: PriceEntry[];
  lowest_price: number;
  lowest_platform: string;
  cached_at: string;
  cache_age_minutes: number;
}

export interface ScanRequest {
  device_uuid: string;
  os: 'ios' | 'android';
  app_version?: string;
  scan_type: 'product' | 'qr_url' | 'qr_wifi' | 'qr_contact' | 'qr_text' | 'isbn' | 'unknown';
  barcode?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  online_prices?: Array<{ platform: string; price: number; is_lowest: boolean }>;
  barcode_content?: {
    raw_value: string;
    content_type: string;
    parsed_data?: Record<string, unknown>;
  } | null;
}
