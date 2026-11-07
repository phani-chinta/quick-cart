import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react';
import type { Session } from '@supabase/supabase-js';
import { isConfigured, supabase } from '../lib/supabase';
import type { CartLine, Category, Product } from '../types/database';

type Shop = { session: Session | null; products: Product[]; categories: Category[]; cart: CartLine[]; loading: boolean; refreshProducts: () => Promise<void>; refreshCart: () => Promise<void>; addToCart: (p: Product) => Promise<void>; changeQuantity: (line: CartLine, amount: number) => Promise<void>; removeFromCart: (line: CartLine) => Promise<void>; signOut: () => Promise<void> };
const ShopContext = createContext<Shop | null>(null);
export function ShopProvider({ children }: { children: ReactNode }) {
 const [session,setSession]=useState<Session|null>(null),[products,setProducts]=useState<Product[]>([]),[categories,setCategories]=useState<Category[]>([]),[cart,setCart]=useState<CartLine[]>([]),[loading,setLoading]=useState(true);
 const refreshProducts=useCallback(async()=>{if(!isConfigured)return; const [{data:ps},{data:cs}]=await Promise.all([supabase.from('products').select('*, category:categories(*)').eq('is_active',true).order('name'),supabase.from('categories').select('*').order('name')]);setProducts(ps??[]);setCategories(cs??[]);},[]);
 const refreshCart=useCallback(async()=>{if(!session||!isConfigured){setCart([]);return;} const {data,error}=await supabase.from('cart_items').select('id,product_id,quantity,product:products(*)');if(error)throw error;setCart((data??[]).flatMap((row)=>row.product? [{id:row.id,product_id:row.product_id,quantity:row.quantity,product:row.product as unknown as Product}]:[]));},[session]);
 useEffect(()=>{if(!isConfigured){setLoading(false);return;} let alive=true; supabase.auth.getSession().then(({data})=>{if(alive){setSession(data.session);setLoading(false);}});const {data:{subscription}}=supabase.auth.onAuthStateChange((_e,s)=>{setSession(s);setLoading(false);});void refreshProducts();return()=>{alive=false;subscription.unsubscribe();};},[refreshProducts]);
 useEffect(()=>{void refreshCart();},[refreshCart]);
 const addToCart=async(p:Product)=>{if(!session)throw new Error('Sign in to add items to your cart.');if(p.stock<1)throw new Error('This item is out of stock.');const existing=cart.find(x=>x.product_id===p.id);if(existing){if(existing.quantity>=p.stock)throw new Error('You’ve reached the available stock.');const {error}=await supabase.from('cart_items').update({quantity:existing.quantity+1}).eq('id',existing.id);if(error)throw error;}else{const {error}=await supabase.from('cart_items').insert({user_id:session.user.id,product_id:p.id,quantity:1});if(error)throw error;}await refreshCart();};
 const changeQuantity=async(line:CartLine,amount:number)=>{const next=line.quantity+amount;if(next<1)return removeFromCart(line);if(next>line.product.stock)throw new Error('You’ve reached the available stock.');const {error}=await supabase.from('cart_items').update({quantity:next}).eq('id',line.id);if(error)throw error;await refreshCart();};
 const removeFromCart=async(line:CartLine)=>{const {error}=await supabase.from('cart_items').delete().eq('id',line.id);if(error)throw error;await refreshCart();};
 const signOut=async()=>{const {error}=await supabase.auth.signOut();if(error)throw error;};
 return <ShopContext.Provider value={{session,products,categories,cart,loading,refreshProducts,refreshCart,addToCart,changeQuantity,removeFromCart,signOut}}>{children}</ShopContext.Provider>;
}
export function useShop(){const value=useContext(ShopContext);if(!value)throw new Error('useShop must be used inside ShopProvider');return value;}
