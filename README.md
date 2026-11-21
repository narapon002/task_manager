# ติดตามโปรเจค (Task Manager)

เว็บแอปติดตามโปรเจคและงานสำหรับองค์กร เป็นหน้าเว็บไฟล์เดียว (`index.html`) ใช้ **Supabase** เป็นฐานข้อมูลและระบบล็อกอิน ผู้ใช้เข้าสู่ระบบด้วย **บัญชี Google (Gmail)**

- เว็บไซต์: https://narapon002.github.io/task_manager/ (เปิดผ่าน GitHub Pages)
- โปรเจค Supabase: `task-manager` (ref `tkzpxogdzebkizxxznrr`, ภูมิภาค Singapore)
- แอดมินคนแรก: `narapon002@gmail.com`

## ไฟล์

| ไฟล์ | หน้าที่ |
|---|---|
| `index.html` | หน้าเว็บทั้งหมด (HTML, CSS, JavaScript) เชื่อม Supabase ผ่าน `supabase-js` |
| `supabase/schema.sql` | โครงสร้างฐานข้อมูล สิทธิ์ (RLS) และ trigger ตรวจสิทธิ์ ติดตั้งในโปรเจคแล้ว ใช้เมื่อต้องสร้างโปรเจคใหม่ |
| `README.md` | คู่มือนี้ |

## การเข้าสู่ระบบและสิทธิ์

1. ผู้ใช้กด **เข้าสู่ระบบด้วย Google**
2. ระบบตรวจว่าอีเมล Google ตรงกับผู้ใช้ในตาราง `members` และสถานะเปิดใช้งาน
3. ถ้าไม่พบหรือถูกปิดการใช้งาน จะเห็นหน้า "ยังไม่มีสิทธิ์เข้าใช้งาน"
4. **แอดมินเพิ่มผู้ใช้ใหม่** ได้ที่หน้า *จัดการผู้ใช้* โดยกรอกอีเมล Gmail ชื่อ ตำแหน่ง ฝ่าย และบทบาท จากนั้นผู้ใช้คนนั้นล็อกอินด้วย Google ได้ทันที

สิทธิ์ของแต่ละบทบาทถูกบังคับที่ฐานข้อมูล (Row Level Security และ trigger) ไม่ใช่แค่ซ่อนปุ่ม ต่อให้เรียก API ตรงก็ทำเกินสิทธิ์ไม่ได้

| การกระทำ | ใครทำได้ |
|---|---|
| ดูโปรเจค งาน และคอมเมนต์ | ผู้ใช้ที่เปิดใช้งานทุกคน |
| สร้างโปรเจค | MD, ผู้จัดการฝ่าย, หัวหน้าแผนก, แอดมิน |
| แก้ไขโปรเจค | ผู้สร้างโปรเจค |
| สร้าง Task | ผู้จัดการฝ่าย, หัวหน้าแผนก, แอดมิน |
| แก้ไขรายละเอียด Task | ผู้สร้าง Task |
| เริ่มงาน / แจ้งติดขัด | ผู้จัดการฝ่าย, แอดมิน, หัวหน้าแผนกในฝ่ายเดียวกัน, ผู้รับผิดชอบ |
| ยืนยันงานเสร็จ (ผู้รับผิดชอบ) | MD, ผู้จัดการฝ่าย, ผู้รับผิดชอบ |
| ยืนยันโดยหัวหน้า / ส่งกลับ / ปลดการยืนยัน | MD, ผู้จัดการฝ่าย, หัวหน้าแผนกในฝ่ายเดียวกัน |
| เพิ่มและแก้ไขข้อมูลผู้ใช้ | แอดมิน |
| เปิด/ปิดการใช้งานผู้ใช้ | MD, ผู้จัดการฝ่าย, หัวหน้าแผนก, แอดมิน |
| ดูประวัติการใช้งาน | MD, แอดมิน |

## ตั้งค่าที่ต้องทำครั้งเดียว (ยังต้องทำเอง)

### 1. สร้าง OAuth Client ใน Google Cloud

1. เปิด https://console.cloud.google.com/ แล้วสร้างโปรเจคใหม่ (หรือใช้โปรเจคเดิม)
2. ไปที่ **APIs & Services > OAuth consent screen**
   - User type: **External**
   - กรอกชื่อแอป เช่น `ติดตามโปรเจค` และอีเมลติดต่อ
   - Scopes ใช้ค่าเริ่มต้น (email, profile, openid)
   - ระหว่างทดลอง ให้เพิ่มอีเมลของทุกคนที่จะใช้ใน **Test users** หรือกด **Publish app** เพื่อให้ทุกบัญชี Google ใช้ได้
3. ไปที่ **APIs & Services > Credentials > Create credentials > OAuth client ID**
   - Application type: **Web application**
   - Authorized JavaScript origins: `https://narapon002.github.io`
   - Authorized redirect URIs: `https://tkzpxogdzebkizxxznrr.supabase.co/auth/v1/callback`
4. คัดลอก **Client ID** และ **Client secret**

### 2. เปิด Google ใน Supabase

1. เปิด https://supabase.com/dashboard/project/tkzpxogdzebkizxxznrr/auth/providers
2. เลือก **Google** แล้วเปิด **Enable Sign in with Google**
3. วาง Client ID และ Client secret แล้วกด Save

### 3. ตั้ง URL ของเว็บใน Supabase

1. เปิด https://supabase.com/dashboard/project/tkzpxogdzebkizxxznrr/auth/url-configuration
2. **Site URL**: `https://narapon002.github.io/task_manager/`
3. **Redirect URLs**: เพิ่ม `https://narapon002.github.io/task_manager/` (ถ้าทดสอบในเครื่อง เพิ่ม `http://localhost:8000/` ด้วย)

### 4. เปิด GitHub Pages

**Settings > Pages** ของ repository: Source เป็น **Deploy from a branch**, Branch **main**, โฟลเดอร์ **/ (root)**

## ทดสอบในเครื่อง

```bash
python3 -m http.server 8000
# เปิด http://localhost:8000/
```

## หมายเหตุด้านความปลอดภัย

- คีย์ใน `index.html` เป็น **publishable key** ซึ่งออกแบบมาให้อยู่ในหน้าเว็บได้ ความปลอดภัยของข้อมูลมาจาก RLS ในฐานข้อมูล
- **ห้าม** ใส่ service_role key หรือ secret key ลงในหน้าเว็บหรือ repository
- Repository นี้เป็น Public ทุกคนเห็นโค้ดได้ แต่จะอ่านข้อมูลได้ต้องล็อกอินด้วยอีเมลที่แอดมินลงทะเบียนไว้เท่านั้น
- โปรเจค Supabase แพ็กเกจฟรีจะ **หยุดชั่วคราว** ถ้าไม่มีการใช้งาน 7 วัน เปิดคืนได้จากหน้า Supabase Dashboard

## สิ่งที่ยังไม่มี

- แนบไฟล์ (วางแผนใช้ Supabase Storage ขนาดไม่เกิน 10 MB)
- ตอบกลับคอมเมนต์ และแจ้งเตือนทางอีเมล
- Gantt แบบเส้นทางวิกฤตและการเลื่อนตารางอัตโนมัติ
- งานประจำและเทมเพลตโปรเจค
