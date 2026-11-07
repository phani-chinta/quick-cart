export type Category = {
  id: string;
  name: string;
  slug: string;
  image_url: string | null;
};

export type Product = {
  id: string;
  category_id: string | null;
  name: string;
  slug: string;
  description: string;
  price: number;
  image_url: string;
  stock: number;
  is_active: boolean;
  category?: Category | null;
};

export type CartLine = {
  id: string;
  product_id: string;
  quantity: number;
  product: Product;
};

export type Database = {
  public: {
    Tables: {
      products: {
        Row: Product;
      };
      categories: {
        Row: Category;
      };
      cart_items: {
        Row: {
          id: string;
          user_id: string;
          product_id: string;
          quantity: number;
        };
      };
      profiles: {
        Row: {
          id: string;
          full_name: string;
          phone: string | null;
        };
      };
      orders: {
        Row: {
          id: string;
          user_id: string;
          total: number;
          status: string;
          payment_method: string;
          created_at: string;
        };
      };
      order_items: {
        Row: {
          id: string;
          order_id: string;
          product_name: string;
          unit_price: number;
          quantity: number;
        };
      };
    };
    Functions: {
      checkout: {
        Args: {
          p_full_name: string;
          p_phone: string;
          p_address: string;
          p_city: string;
          p_state: string;
          p_postal_code: string;
        };
        Returns: string;
      };
    };
  };
};
