/**
 * โปรโตไทป์ติดตามโปรเจค (ทดลอง) — Google Apps Script
 *
 * ไฟล์นี้ทำหน้าที่เสิร์ฟหน้าเว็บ index.html เป็นเว็บแอป
 * ยังไม่มีฐานข้อมูล ข้อมูลทั้งหมดอยู่ในเบราว์เซอร์ของแต่ละคนและหายเมื่อรีโหลด
 *
 * วิธีใช้: สร้างโปรเจค Apps Script แล้วสร้างไฟล์ index.html ให้วางเนื้อหาจาก index.html
 * จากนั้น Deploy > New deployment > Web app
 */
function doGet(e) {
  return HtmlService.createHtmlOutputFromFile('index')
    .setTitle('ติดตามโปรเจค (ทดลอง)')
    .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL)
    .addMetaTag('viewport', 'width=device-width, initial-scale=1');
}
