create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '', phone text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.categories (
  id uuid primary key default gen_random_uuid(), name text not null unique,
  slug text not null unique, image_url text, created_at timestamptz not null default now()
);
create table public.products (
  id uuid primary key default gen_random_uuid(), category_id uuid references public.categories(id),
  name text not null, slug text not null unique, description text not null default '',
  price numeric(12,2) not null check (price >= 0), image_url text not null,
  stock integer not null default 0 check (stock >= 0), is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.cart_items (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  quantity integer not null check (quantity between 1 and 99), created_at timestamptz not null default now(),
  unique(user_id,product_id)
);
create table public.orders (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id),
  full_name text not null, phone text not null, address text not null, city text not null,
  state text not null, postal_code text not null,
  total numeric(12,2) not null check(total >= 0), payment_method text not null default 'cod' check(payment_method='cod'),
  status text not null default 'pending' check(status in ('pending','confirmed','shipped','delivered','cancelled')),
  created_at timestamptz not null default now()
);
create table public.order_items (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null, product_name text not null,
  unit_price numeric(12,2) not null check(unit_price >= 0), quantity integer not null check(quantity > 0),
  created_at timestamptz not null default now()
);
create index products_category_active_idx on public.products(category_id,is_active);
create index cart_user_idx on public.cart_items(user_id);
create index orders_user_created_idx on public.orders(user_id,created_at desc);
create index order_items_order_idx on public.order_items(order_id);

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.profiles(id,full_name) values(new.id,coalesce(new.raw_user_meta_data->>'full_name','')); return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();
create or replace function public.touch_updated_at() returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end $$;
create trigger profiles_updated_at before update on public.profiles for each row execute procedure public.touch_updated_at();
create trigger products_updated_at before update on public.products for each row execute procedure public.touch_updated_at();

create or replace function public.guard_cart_stock() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_stock integer; v_active boolean;
begin
 select stock,is_active into v_stock,v_active from public.products where id=new.product_id;
 if not found or not v_active then raise exception 'This product is unavailable'; end if;
 if new.quantity>v_stock then raise exception 'Quantity exceeds available stock'; end if;
 return new;
end $$;
create trigger cart_stock_guard before insert or update of product_id,quantity on public.cart_items for each row execute procedure public.guard_cart_stock();

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.cart_items enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
create policy "Profiles are readable by owner" on public.profiles for select to authenticated using(id=auth.uid());
create policy "Profiles are created by owner" on public.profiles for insert to authenticated with check(id=auth.uid());
create policy "Profiles are updated by owner" on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy "Categories are public" on public.categories for select to anon,authenticated using(true);
create policy "Active products are public" on public.products for select to anon,authenticated using(is_active=true);
create policy "Users read own cart" on public.cart_items for select to authenticated using(user_id=auth.uid());
create policy "Users add own cart items" on public.cart_items for insert to authenticated with check(user_id=auth.uid());
create policy "Users update own cart items" on public.cart_items for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy "Users remove own cart items" on public.cart_items for delete to authenticated using(user_id=auth.uid());
create policy "Users read own orders" on public.orders for select to authenticated using(user_id=auth.uid());
create policy "Users read own order items" on public.order_items for select to authenticated using(exists(select 1 from public.orders o where o.id=order_id and o.user_id=auth.uid()));

create or replace function public.checkout(p_full_name text,p_phone text,p_address text,p_city text,p_state text,p_postal_code text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_order uuid; v_total numeric(12,2); v_cart_count integer;
begin
 if auth.uid() is null then raise exception 'Sign in before placing an order'; end if;
 if length(trim(p_full_name))<2 or length(trim(p_phone))<10 or length(trim(p_address))<8 or length(trim(p_city))<2 or length(trim(p_state))<2 or p_postal_code !~ '^\d{6}$' then raise exception 'Please check your delivery details'; end if;
 select count(*) into v_cart_count from public.cart_items where user_id=auth.uid();
 if v_cart_count=0 then raise exception 'Your cart is empty'; end if;
 perform p.id from public.products p join public.cart_items c on c.product_id=p.id where c.user_id=auth.uid() order by p.id for update of p;
 if exists(select 1 from public.cart_items c join public.products p on p.id=c.product_id where c.user_id=auth.uid() and (p.is_active=false or p.stock<c.quantity)) then raise exception 'An item is no longer available in the requested quantity'; end if;
 select sum(p.price*c.quantity) into v_total from public.cart_items c join public.products p on p.id=c.product_id where c.user_id=auth.uid();
 insert into public.orders(user_id,full_name,phone,address,city,state,postal_code,total) values(auth.uid(),trim(p_full_name),trim(p_phone),trim(p_address),trim(p_city),trim(p_state),trim(p_postal_code),v_total) returning id into v_order;
 insert into public.order_items(order_id,product_id,product_name,unit_price,quantity) select v_order,p.id,p.name,p.price,c.quantity from public.cart_items c join public.products p on p.id=c.product_id where c.user_id=auth.uid();
 update public.products p set stock=p.stock-c.quantity from public.cart_items c where c.user_id=auth.uid() and c.product_id=p.id;
 delete from public.cart_items where user_id=auth.uid();
 return v_order;
end $$;
revoke all on function public.checkout(text,text,text,text,text,text) from public;
grant execute on function public.checkout(text,text,text,text,text,text) to authenticated;

insert into public.categories(name,slug,image_url) values
 ('Electronics','electronics','https://images.unsplash.com/photo-1505740420928-5e560c06d30e?auto=format&fit=crop&w=700&q=82'),
 ('Fashion','fashion','https://images.unsplash.com/photo-1483985988355-763728e1935b?auto=format&fit=crop&w=700&q=82'),
 ('Accessories','accessories','https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&w=700&q=82'),
 ('Home & Living','home-living','https://images.unsplash.com/photo-1616486338812-3dadae4b4ace?auto=format&fit=crop&w=700&q=82'),
 ('Lifestyle','lifestyle','https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=700&q=82');
insert into public.products(category_id,name,slug,description,price,image_url,stock) values
 ((select id from public.categories where slug='electronics'),'Studio wireless headphones','studio-wireless-headphones','Immersive sound, considered comfort. A long-lasting companion for wherever the day takes you.',8490,'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?auto=format&fit=crop&w=900&q=85',24),
 ((select id from public.categories where slug='electronics'),'Portable Bluetooth speaker','portable-bluetooth-speaker','Rich, room-filling sound in a beautifully compact, travel-ready form.',5290,'https://images.unsplash.com/photo-1608043152269-423dbba4e7e1?auto=format&fit=crop&w=900&q=85',18),
 ((select id from public.categories where slug='electronics'),'Everyday smart watch','everyday-smart-watch','Thoughtful wellness tools and everyday utility, all in a clean, comfortable design.',11990,'https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&w=900&q=85',12),
 ((select id from public.categories where slug='electronics'),'Pocket instant camera','pocket-instant-camera','Make small moments tangible with a compact instant camera made for the everyday.',7290,'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?auto=format&fit=crop&w=900&q=85',9),
 ((select id from public.categories where slug='fashion'),'Classic canvas sneakers','classic-canvas-sneakers','A versatile low-profile sneaker with durable canvas and a comfortable everyday sole.',3490,'https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=900&q=85',30),
 ((select id from public.categories where slug='fashion'),'Relaxed cotton overshirt','relaxed-cotton-overshirt','An easy layer in breathable cotton, with clean lines and a relaxed, considered fit.',4290,'https://images.unsplash.com/photo-1598033129183-c4f50c736f10?auto=format&fit=crop&w=900&q=85',16),
 ((select id from public.categories where slug='fashion'),'Everyday leather trainers','everyday-leather-trainers','Soft leather uppers and a quietly versatile silhouette for daily miles.',5990,'https://images.unsplash.com/photo-1549298916-b41d501d3772?auto=format&fit=crop&w=900&q=85',21),
 ((select id from public.categories where slug='fashion'),'Essential weekend tote','essential-weekend-tote','A roomy, sturdy carryall made for market mornings and spontaneous weekends.',1990,'https://images.unsplash.com/photo-1590874103328-eac38a683ce7?auto=format&fit=crop&w=900&q=85',33),
 ((select id from public.categories where slug='accessories'),'Minimal everyday watch','minimal-everyday-watch','A timeless, easy-wearing timepiece with a clean dial and thoughtful detailing.',6790,'https://images.unsplash.com/photo-1524592094714-0f0654e20314?auto=format&fit=crop&w=900&q=85',14),
 ((select id from public.categories where slug='accessories'),'Sculpted silver hoops','sculpted-silver-hoops','Lightweight, responsibly crafted hoops with a subtle sculptural profile.',2490,'https://images.unsplash.com/photo-1535632066927-ab7c9ab60908?auto=format&fit=crop&w=900&q=85',26),
 ((select id from public.categories where slug='accessories'),'Everyday carry backpack','everyday-carry-backpack','A considered, weather-ready backpack with just the right amount of organization.',4890,'https://images.unsplash.com/photo-1553062407-98eeb64c6a62?auto=format&fit=crop&w=900&q=85',11),
 ((select id from public.categories where slug='accessories'),'Soft frame sunglasses','soft-frame-sunglasses','An easy-to-wear acetate frame with full UV protection and timeless proportions.',3190,'https://images.unsplash.com/photo-1511499767150-a48a237f0083?auto=format&fit=crop&w=900&q=85',19),
 ((select id from public.categories where slug='home-living'),'Hand-thrown ceramic mug','hand-thrown-ceramic-mug','A softly textured ceramic mug, made for slow mornings and second cups.',890,'https://images.unsplash.com/photo-1514228742587-6b1558fcca3d?auto=format&fit=crop&w=900&q=85',40),
 ((select id from public.categories where slug='home-living'),'Linen cushion cover','linen-cushion-cover','Naturally textured linen that brings an understated softness to your space.',1490,'https://images.unsplash.com/photo-1584100936595-c0654b55a2e2?auto=format&fit=crop&w=900&q=85',27),
 ((select id from public.categories where slug='home-living'),'Ambient table lamp','ambient-table-lamp','Warm, gentle light in a quiet sculptural form. Made for the softer hours.',4590,'https://images.unsplash.com/photo-1507473885765-e6ed057f782c?auto=format&fit=crop&w=900&q=85',8),
 ((select id from public.categories where slug='lifestyle'),'Insulated daily bottle','insulated-daily-bottle','Keep your favourite drink close with a durable insulated bottle for every day.',1290,'https://images.unsplash.com/photo-1602143407151-7111542de6e8?auto=format&fit=crop&w=900&q=85',44),
 ((select id from public.categories where slug='lifestyle'),'Journal for small ideas','journal-for-small-ideas','A tactile, lay-flat notebook for lists, thoughts and whatever comes next.',690,'https://images.unsplash.com/photo-1531346878377-a5be20888e57?auto=format&fit=crop&w=900&q=85',52),
 ((select id from public.categories where slug='lifestyle'),'Everyday yoga mat','everyday-yoga-mat','A grounded, cushioned mat for daily movement, stretching and a moment to yourself.',2590,'https://images.unsplash.com/photo-1599447421416-3414500d18a5?auto=format&fit=crop&w=900&q=85',15);
