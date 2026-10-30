# Kama Jeweller — App Kaise Kaam Karti Hai

**App:** RFID Jewellery Handheld  
**Client:** Kama Jeweller  
**Report date:** 29 October 2026  
**Purpose:** Shop staff aur admin ke liye har home tab ka kaam, flow, aur Settings ka poora section-wise guide.

---

## 1. App ek nazar mein

Yeh handheld RFID app jewellery stock ko tag se pehchanne, ginne, transfer karne, order / quotation / challan banane, aur daily gold rate update karne ke liye hai.

Login ke baad **Home** screen khulti hai. Wahan 12 tiles hain. Wahi menu left drawer mein bhi hai, saath mein **Home** aur **Logout**.

| Home tile | Kaam |
| --- | --- |
| Product | Naya item add, Excel, server sync, product list |
| Inventory | Counter / box / branch / exhibition scan aur stock match |
| Order | Customer order banana aur purani orders dekhna |
| Search | Tag, order, ya box ko RFID se dhoondhna |
| Stock Transfer | Stock ek jagah se doosri jagah bhejna aur request approve karna |
| Report | Scan session ka verification report |
| Quotations | Customer ko rate quotation |
| Delivery Challan | Delivery challan banana aur print |
| Label Today Rate | Category + purity ka aaj ka rate (per gram) |
| Sample In | Bahar gaye sample ka wapas aana |
| Sample Out | Customer ko sample dena |
| Settings | Power, language, backup, API, face login, aur baaki setup |

Kama login par do extra cheezein milti hain:

- **Inventory → Scan missing Stocks**
- **Settings → Wholesale option** (is handset ka branch aur counter)

App English, Hindi, aur Arabic mein chal sakti hai. Language **Settings → Language** se badalti hai.

---

## 2. Login aur Home

### Login

1. Username aur password daalein.
2. **Remember Me** on ho to agle baar fields khud bhar jaati hain.
3. Login success ke baad Home khulta hai.
4. Face login tabhi chalta hai jab **Settings → Face data** se face pehle save ho chuka ho.

Login ke baad app Bluetooth RFID reader check karti hai. Agar location sync on hai aur permission nahi di, to kuch seconds baad background location ki permission maangi jaati hai.

### Home

- Tile par tap karke us module mein jaayein.
- Drawer se bhi wahi screens khulti hain.
- **Logout** session band karta hai aur login screen par laata hai.
- Har scan screen par upar **RFID power** (1 se 30) hai. Power jitni zyada, tag utni door se padhta hai. Module-wise default power Settings ke pehle paanch rows se set hoti hai.

---

## 3. Product

Product tile product master aur labelled stock ka control hai. Andar 8 cards hain, neeche **Open Product List**.

### Add Single Product

Ek item ka form. Fields isi order mein hain:

EPC, Vendor, SKU, RFID Code, Category, Product, Design, Purity, Gross Weight, Stone Weight, Diamond Weight, Net Weight, Making/Gram, Making %, Fix Making, Fix Wastage, Stone Amount, Diamond Amount.

- Category pehle choose karein, phir Product, phir Design, phir Purity. Agli list tabhi bharti hai jab pichhli select ho.
- SKU choose karne par Category, Product, Design, Purity lock ho sakte hain.
- **Net Weight** khud calculate hota hai (gross − stone − diamond). Use type nahi karte.
- EPC aur RFID Code RFID gun se scan ho sakte hain.
- Neeche scan bar: **Save**, **List**, single **Scan**, **Gscan** (continuous), **Reset**.

### Add Bulk Products

Ek saath kai items. Dropdowns (category, product, design, purity, vendor) pehle load hote hain, phir rows add karke save.

### Import Excel

Excel file se products device par laate hain. Column mapping dialog mein file ke columns ko app fields se jodna hota hai, phir import.

### Export Excel

Jo stock device par synced hai, use Excel bana kar share karta hai. Agar local data khali hai to pehle **Sync Data** karna padta hai.

### Sync Data

Server se product / labelled stock device ke local database mein laata hai. Progress percent dikhta hai. Complete hone par success dialog aata hai. Jo item codes skip hue, unki short list bhi dikhti hai.

Scan, search, order, aur transfer isi local stock par chalte hain. Naya maal server par aane ke baad yahan sync zaroori hai.

### Scan to Desktop

Handheld par scan karke data usi Wi‑Fi par desktop ko bhejne ka screen. **Settings → Local WiFi mode** on hona chahiye, aur phone aur computer same network par hone chahiye.

### Sync Sheet Data

Google Sheet se data laata hai. Sheet ka URL **Settings → Sheet URL** mein pehle save hona chahiye.

### Upload Data to Server

Device par jo naya / updated product data hai, use server par bhejta hai.

### Open Product List

Synced products ki list.

- Search: SKU, item code, ya name.
- Filter: category / product / design.
- Edit: item kholta hai, fields badal kar save.
- Delete: confirm ke baad item hataata hai.
- PDF export: current list ka PDF share.

---

## 4. Inventory

Inventory stock ginne aur match karne ka module hai. Pehle filter choose karte hain, phir scan screen khulti hai.

| Button | Kya hota hai |
| --- | --- |
| Scan Display | Poora labelled stock, bina filter |
| Scan missing Stocks | Sirf Kama / wholesale login. Jo stock is branch-counter par missing hai, use scan karke match |
| Scan Counter | Ek ya zyada counter choose karke unka stock scan |
| Scan Box | Ek ya zyada box choose karke scan |
| Scan Branch | Ek ya zyada branch choose karke scan |
| Exhibition | Exhibition choose karke scan |

Counter, Box, Branch, aur Exhibition par multi-select dialog aata hai. Kuch na mile to “no data” message aata hai. Confirm par **Scan Display** us filter ke saath khulta hai.

### Scan Display par kaam

1. Gun ka trigger ya beech ka **Scan** button dabayein. **Gscan** lagatar padhta hai, dubara dabane par stop.
2. Jo tag master stock mein hai wo **Matched** hota hai. Jo expected list mein nahi milta wo **Unmatched**. Jis tag par label/item code nahi, wo **Unlabelled**.
3. Left list menu:
   - Matched items (count)
   - Unmatched items (count)
   - Unlabelled items (count)
   - Resume scan
   - Search unmatched — unmatched tags ko Search screen par le jaata hai, taaki gun se unhe physically dhoondha ja sake
4. Upar **Print** se scan report PDF.
5. Email se report bhej sakte hain (saved emails).
6. Filter icon se category / product / design / date filter. Date filter hatane par live scan delete nahi hota.
7. Power icon se is screen ki RFID power.

Scan khatam karke save karne par session report mein **BatchWise** ke roop mein dikhta hai.

---

## 5. Order

Home se seedha **order list** khulti hai.

### List

Columns: order id, customer, qty, gross weight, net weight, amount, status, date.

- Search se order dhoondhein.
- **Report & Filters**:
  - All Orders List
  - SKU Wise Order Summary
  - Customer Wise Order Summary
  - Date range (order date ya doosra date field) aur status filter
- Sync: jo orders offline save hue, unhe server par bhejta hai. Success par “data sync successfully”.
- Delete: confirm ke baad order hatata hai.
- **+** se naya order.

### Naya order

1. Customer name search karein. Naya customer **Customer Profile** se add ho sakta hai. Net na ho to customer offline save hota hai.
2. Item code type karein, ya RFID se **Scan / Gscan**.
3. Items ki table: qty, weights, amount. Galat line delete ho sakti hai.
4. GST aur total amount neeche dikhte hain.
5. Kam se kam ek item ke bina save nahi hota.
6. Save online ho to “order saved”. Net na ho to “order saved offline”, baad mein list se sync.

Purana order khol kar update bhi hota hai.

---

## 6. Search

Tag ko shelf par dhoondhne ka screen. Type teen hain:

| Search type | Kya dhoondhte hain | Box mein kya likhein |
| --- | --- | --- |
| LabelStock | Labelled jewellery | RFID ya item code |
| Order | Order ki items | RFID ya custom order id |
| Box | Box | RFID ya box RFID |

Flow:

1. Type choose karein.
2. Code / RFID likhein ya scan karein. Scan chalte waqt type change nahi hoti.
3. List mein RFID, item code, progress bar, aur **percent** dikhta hai. Percent tag ki nazdeeki (RSSI) hai — jitna zyada, tag utna paas.
4. Power badha kar door ka tag, kam karke exact piece alag karte hain.

Inventory ke **Search unmatched** se yahi screen unmatched list ke saath khulti hai. Wahan text search RFID / item code par hai, aur paas wale tags upar aa jaate hain.

---

## 7. Stock Transfer

Stock ek location se doosri location (counter, box, branch) bhejne ka module.

### Naya transfer

Upar teen chips:

1. **Transfer Type** — server se aane wale types (jaise counter to box, branch to branch).
2. **From** — kahan se.
3. **To** — kahan tak.

Phir:

- Item code search se piece tick karein, ya RFID **Scan / Gscan** se tick ho jaayein.
- Filter (tune icon): Category, Product, Design. Apply ya Clear.
- Header checkbox se saari visible rows select.
- Neeche totals: **T qty** (list ki qty), **Set Qty** (selected), **Gr wt**, **ntWt**.

**Save** tabhi aage badhta hai jab From, To, aur kam se kam ek item selected ho.

### Preview aur submit

Preview par selected lines dikhti hain. Jo line nahi bhejni, use hata sakte hain.

**Transfer** dabane par details:

- Kaun bhej raha hai (logged-in user).
- Branch-to-branch par **kis employee ko** bhejna hai, ye choose karna zaroori hai.
- Remarks.

OK par transfer server par create hota hai. Success par form khaali ho jaata hai.

### In Request aur Out Request

Neeche **List** se popup:

- **In Request** — is branch / user ke paas aane wali transfers.
- **Out Request** — yahan se gayi hui transfers.

List par transfer type aur status filter hai. Row kholne par item lines.

**Approve / Reject / Lost** In Request par, ya Out Request par tab jab self-approval ho. Pending lines select karke action karte hain. Approve ke baad stock nayi location par sync hota hai.

---

## 8. Report

Home ka **Report** tile **Stock Verification Report** hai. Yahi inventory scan ka hisaab hai.

Do tabs:

| Tab | Matlab |
| --- | --- |
| BatchWise | Har scan session alag. Date, branch, counts. Session kholne par us batch ki detail |
| Consolidated | Ek date par branch → category → product → design ka tree. Total / matched / unmatched drill-down |

- Date picker se din choose.
- Filter se branch aur from–to date (batch list par).
- Download icon se Excel export. Progress dikhta hai.
- Khaali din par “no sessions” / “no data for selected date”.

Detail screen par type (TOTAL aur related) ke hisaab se item lines khulti hain.

---

## 9. Quotations

Customer ko likhit rate quote.

### List

Search quotation number, customer, ya description se. Columns: Q No, customer (khali ho to Walk-in), description, date, qty, gross / stone / diamond weight, aur amounts.

**+** se naya quotation. Refresh se list dubara load.

### Naya quotation

1. Customer search ya naya customer profile.
2. Item code / RFID se lines add. **Scan** aur **Gscan** dono hain. Power upar se.
3. Kam se kam ek item.
4. Quotation details (remark wagairah) bhar kar save.
5. List se purana quotation khol kar dekh / update.

---

## 10. Delivery Challan

Samaan bahar bhejne ka challan.

### List

Search challan number / customer. Columns mein challan no, date, customer, qty, weights.

**+** naya challan. Refresh list reload. Khaali ho to “create challan” hint.

### Naya challan

1. Customer name. Naya customer yahin se add.
2. RFID ya item code se lines. Galat line delete (confirm).
3. Save.
4. Challan details dialog se fields check karke **PDF** share / print.

---

## 11. Label Today Rate

Jewellery label par lagane wala **aaj ka rate, per gram**.

Screen par table:

| Category | Purity | Today rate / gm |
| --- | --- | --- |

- Rate number mein likhein. Ek hi decimal point.
- **Update** server par save karta hai. Success: “rates updated”.
- **Cancel** Home par wapas, bina save.
- Rates khali hon to error / “no rates” message.

Yahi rate order, quotation, aur label calculation mein use hota hai, isliye subah dukaan khulte hi update karna sahi rehta hai.

---

## 12. Sample Out

Customer ko gehna trial / approval ke liye dena.

### List

Search sample-out number, customer, ya product. Columns: SO No, customer, date, return date, description, product, weights.

**+** naya sample out. Refresh list reload.

### Naya sample out

1. Customer choose ya naya customer.
2. Product lines item code / RFID se. Scan aur Gscan.
3. Return date aur description.
4. Line delete ho sakti hai.
5. Save.
6. Print PDF se customer copy.

Sample Out ke bina Sample In ka match nahi banta, kyunki wapas aane wala maal isi SO number se judta hai.

---

## 13. Sample In

Jo sample bahar gaya, uska wapas aana.

### List

Search SO number, customer, ya product. Columns: SO No, customer, date, return date (R Date), description, product name, item code, RFID, total / gross / stone / diamond weight.

### Naya sample in

1. Customer aur uska **Sample Out** choose karein. Bina challan / issue items ke aage nahi badhta.
2. Jo pieces wapas aaye, unhe scan karein.
3. Tag us SO ki issue list se match ho to **Confirm match** dialog. **Yes** par line matched list mein.
4. Galat match **Remove match** se hatata hai.
5. Save par sample-in record banता hai aur list mein dikhta hai.

Isse pata chalta hai kaun sa sample abhi bhi customer ke paas hai aur kaun sa wapas aa gaya.

---

## 14. Settings — har section

Settings ki list upar se neeche isi order mein hai.

### Product / Inventory / Search / Order / Stock Transfer (power)

Har row ke number par tap karke **1–30** RFID power. Yeh us module ki default power hai. Screen ke andar bhi power badal sakte hain; wahan ka choice us module ki saved power ko update karta hai.

### Language

English, Hindi, ya Arabic. Save par poori app us bhasha mein ho jaati hai. Arabic par text right-to-left.

### Location

Switch se location sync on / off.

- On karte hi background location ki permission. Mana karne par sync off rehta hai.
- On hone par location lagbhag **har 15 minute** save hoti hai.
- Row par tap **location list** kholta hai — save hue points.

### Account

Saved username dikhta hai. Password dots mein. Yahan se password change nahi hota.

### User Permission

Message: permissions server se aati hain. Jo user login hai, uske rights (approve, scan, wagairah) server user permission se aate hain. Is row par edit nahi hai.

### Email

Logged-in employee ka email dikhta hai. Khali ho to default login email. Row tap se edit nahi hota.

### Backup

Teen option:

| Option | Kaam |
| --- | --- |
| Save to device | Local database ki file device par save. Path snackbar mein |
| Send via email | Email daalein, backup us par jaata hai. Last email yaad rehta hai |
| Restore backup | Pehle save ki hui file se data wapas |

### Auto sync

Switch aur interval: **15 min, 30 min, 1 hour, 24 hours**. On hone par app khud server se data sync karti hai. Handheld par heavy sync ke dauran screen slow ho sakti hai, isliye interval dukaan ke hisaab se rakhein.

### Notifications

Enable / disable. Save.

### Branches

Is user ke selected branch IDs sirf dikhte hain. Yahan se branch add nahi hoti; assignment server / login se aati hai.

### Wholesale option (sirf Kama login)

Kama client par yeh row dikhti hai. Trailing text mein pehla branch · counter, aur agar zyada assignment hon to `+N`.

Andar:

- Device id (handset ka stable id, khud nahi badalta).
- Branch choose.
- Us branch ke counters checkbox se.
- Save. Yahi assignment **Scan missing Stocks** aur branch-counter scan ko batati hai ki yeh gun kis counter ka hai.

Agar server par is device ki RFID assignment na ho to “device config not found” aa sakta hai. Us case mein device id admin ko dekar server par map karwana hota hai.

### Custom API

Server base URL. Khali chhodne par default server use hota hai. URL `http://` ya `https://` ke bina ho to app khud laga deti hai. Sirf authorized URL save karein.

### Sheet URL

Google Sheet ka link. **Product → Sync Sheet Data** isi URL ko padhta hai.

### Stock Transfer URL

Stock transfer API ka alag URL, agar transfer default server par nahi hai.

### Privacy policy

Privacy policy screen khulti hai.

### Face data

Naya face enrol. Iske baad login screen par face se login ho sakta hai.

### Local WiFi mode

- Off: normal internet.
- On: phone Wi‑Fi par hona chahiye. App IP dikhati hai, jaise `http://<phone-ip>:8080/rfid-data`. Desktop isi address se handheld ka scan data leta hai (**Scan to Desktop**). Wi‑Fi na ho to mode on nahi hota.

### Reusable tags

- Off: sirf web reusable tags.
- On: single reusable tag bhi allow. Snackbar current mode batata hai.

### Clear data

Local data (products, scans, saved session) mitaata hai.

1. Confirm dialog.
2. Login password.
3. Password sahi ho to data clear aur seedha login screen. Galat password par “incorrect password”, data rehta hai.

Clear se pehle **Backup → Save to device** kar lena chahiye.

---

## 15. Kama par ek normal din

1. Login.
2. **Label Today Rate** update.
3. **Product → Sync Data**, taaki naya labelled stock gun par aa jaaye.
4. Counter par **Inventory → Scan Counter** (ya Scan Display) se physical stock match.
5. Jo tag nahi mila, **Search unmatched** se dhoondhein.
6. Jis counter se maal shift karna ho, **Stock Transfer**. Doosri branch se aaya maal **List → In Request → Approve**.
7. Customer order **Order**, quote **Quotations**, bahar jaane wala maal **Delivery Challan**.
8. Trial par diya gehna **Sample Out**, wapas aaya to **Sample In** par usi SO se match.
9. Din khatam **Report → BatchWise** se aaj ki scan sessions dekhein. Zarurat ho to Excel.
10. Hafte mein ek baar **Settings → Backup → Save to device**.

---

## 16. Jo cheezein yaad rakhni hain

- Bina **Sync Data** ke scan purana stock dikhayega.
- RFID power bahut zyada ho to bagal ke counter ke tag bhi padh lega. Counter scan par power kam rakhein.
- Order, customer, aur transfer net ke bina local save ho sakte hain. Net aate hi list ka sync dabayein.
- Kama par **Wholesale option** sahi branch-counter par hona chahiye, warna missing-stock scan galat list dikhayega.
- **Clear data** password maangta hai aur logout kar deta hai. Backup ke bina use na karein.
