# Delivery Challan — one model for List and Create

Create Delivery Challan aur Delivery Challan List **same `PageControls` model** use karenge. `key`, `type`, `place`, aur `visibility` dono pages pe same hain. Sirf `PageName` alag hai.

`Id` suggested hain. Server apna real `Id` de sakta hai. `key` change mat karna.

## Rules

| Field | Values |
| --- | --- |
| `PagePermission` | `enable` / `disable` |
| `Create` `Edit` `Delete` `Full` | `true` / `false` |
| `isMobView` | `true` |
| `type` | `text`, `search`, `dropdown`, `date`, `number`, `checkbox`, `label`, `action` |
| `visibility` | `ReadWrite`, `ReadOnly`, `Hidden` |
| `place` | `top`, `dialog`, `table`, `bottom`, `action` |
| `priority` | chhota number pehle dikhega |

`Hidden` render nahi hogi. `ReadOnly` dikhegi, edit nahi hogi.

## Payload

Dono modules ka `PageControls` array **byte-for-byte same** hai.

```json
[
  {
    "Modules": [
      {
        "PageName": "create_delivery_challan",
        "PageDisplayName": "Create Delivery Challan",
        "PagePermission": "enable",
        "Create": true,
        "Edit": true,
        "Delete": true,
        "Full": true,
        "isMobView": true,
        "PageControls": []
      },
      {
        "PageName": "delivery_challan_list",
        "PageDisplayName": "Delivery Challan List",
        "PagePermission": "enable",
        "Create": true,
        "Edit": true,
        "Delete": true,
        "Full": true,
        "isMobView": true,
        "PageControls": []
      }
    ]
  }
]
```

`PageControls` (dono pages pe yahi array paste karo):

```json
[
  {
    "Id": 960001,
    "key": "customerName",
    "label": "Customer Name",
    "placeholder": "Enter customer name",
    "priority": 1,
    "type": "search",
    "visibility": "ReadWrite",
    "place": "top"
  },
  {
    "Id": 960002,
    "key": "rfidItemCode",
    "label": "RFID / Itemcode",
    "placeholder": "Enter RFID / Itemcode",
    "priority": 2,
    "type": "search",
    "visibility": "ReadWrite",
    "place": "top"
  },
  {
    "Id": 960003,
    "key": "challanNo",
    "label": "Challan No",
    "placeholder": "Search Challan No or Customer Name",
    "priority": 3,
    "type": "search",
    "visibility": "ReadWrite",
    "place": "top"
  },
  {
    "Id": 960004,
    "key": "challanFields",
    "label": "Challan Fields",
    "placeholder": "",
    "priority": 4,
    "type": "action",
    "visibility": "ReadWrite",
    "place": "top"
  },
  {
    "Id": 960011,
    "key": "branch",
    "label": "Branch",
    "placeholder": "Select branch",
    "priority": 1,
    "type": "dropdown",
    "visibility": "ReadWrite",
    "place": "dialog"
  },
  {
    "Id": 960012,
    "key": "date",
    "label": "Date",
    "placeholder": "",
    "priority": 2,
    "type": "date",
    "visibility": "ReadWrite",
    "place": "dialog"
  },
  {
    "Id": 960013,
    "key": "finePercent",
    "label": "Fine %",
    "placeholder": "",
    "priority": 3,
    "type": "number",
    "visibility": "ReadWrite",
    "place": "dialog"
  },
  {
    "Id": 960014,
    "key": "wastagePercent",
    "label": "Wastage %",
    "placeholder": "",
    "priority": 4,
    "type": "number",
    "visibility": "ReadWrite",
    "place": "dialog"
  },
  {
    "Id": 960015,
    "key": "salesman",
    "label": "Salesman",
    "placeholder": "Select salesman",
    "priority": 5,
    "type": "dropdown",
    "visibility": "ReadWrite",
    "place": "dialog"
  },
  {
    "Id": 960101,
    "key": "srNo",
    "label": "S.No",
    "placeholder": "",
    "priority": 1,
    "type": "label",
    "visibility": "ReadOnly",
    "place": "table"
  },
  {
    "Id": 960102,
    "key": "itemName",
    "label": "Item Name",
    "placeholder": "",
    "priority": 2,
    "type": "label",
    "visibility": "ReadOnly",
    "place": "table"
  },
  {
    "Id": 960103,
    "key": "itemCode",
    "label": "Item Code",
    "placeholder": "",
    "priority": 3,
    "type": "label",
    "visibility": "ReadOnly",
    "place": "table"
  },
  {
    "Id": 960104,
    "key": "qty",
    "label": "Qty",
    "placeholder": "",
    "priority": 4,
    "type": "number",
    "visibility": "ReadOnly",
    "place": "table"
  },
  {
    "Id": 960105,
    "key": "grossWt",
    "label": "Gross Wt",
    "placeholder": "",
    "priority": 5,
    "type": "number",
    "visibility": "ReadOnly",
    "place": "table"
  },
  {
    "Id": 960106,
    "key": "stoneWt",
    "label": "Stone Wt",
    "placeholder": "",
    "priority": 6,
    "type": "number",
    "visibility": "ReadOnly",
    "place": "table"
  },
  {
    "Id": 960107,
    "key": "diamondWt",
    "label": "Diamond Wt",
    "placeholder": "",
    "priority": 7,
    "type": "number",
    "visibility": "ReadOnly",
    "place": "table"
  },
  {
    "Id": 960108,
    "key": "netWt",
    "label": "Net Wt",
    "placeholder": "",
    "priority": 8,
    "type": "number",
    "visibility": "ReadOnly",
    "place": "table"
  },
  {
    "Id": 960109,
    "key": "rate",
    "label": "Rate",
    "placeholder": "",
    "priority": 9,
    "type": "number",
    "visibility": "ReadOnly",
    "place": "table"
  },
  {
    "Id": 960110,
    "key": "makingCharge",
    "label": "Making Chg",
    "placeholder": "",
    "priority": 10,
    "type": "number",
    "visibility": "ReadOnly",
    "place": "table"
  },
  {
    "Id": 960111,
    "key": "stoneAmount",
    "label": "Stone Amt",
    "placeholder": "",
    "priority": 11,
    "type": "number",
    "visibility": "ReadOnly",
    "place": "table"
  },
  {
    "Id": 960112,
    "key": "diamondAmount",
    "label": "Diamond Amt",
    "placeholder": "",
    "priority": 12,
    "type": "number",
    "visibility": "ReadOnly",
    "place": "table"
  },
  {
    "Id": 960113,
    "key": "fineWt",
    "label": "Fine Wt",
    "placeholder": "",
    "priority": 13,
    "type": "number",
    "visibility": "ReadOnly",
    "place": "table"
  },
  {
    "Id": 960114,
    "key": "taxAmount",
    "label": "Tax Amt",
    "placeholder": "",
    "priority": 14,
    "type": "number",
    "visibility": "ReadOnly",
    "place": "table"
  },
  {
    "Id": 960115,
    "key": "amount",
    "label": "Amount",
    "placeholder": "",
    "priority": 15,
    "type": "number",
    "visibility": "ReadOnly",
    "place": "table"
  },
  {
    "Id": 960116,
    "key": "totalAmount",
    "label": "Total Amount",
    "placeholder": "",
    "priority": 16,
    "type": "number",
    "visibility": "ReadOnly",
    "place": "table"
  },
  {
    "Id": 960117,
    "key": "rfid",
    "label": "RFID",
    "placeholder": "",
    "priority": 17,
    "type": "label",
    "visibility": "ReadOnly",
    "place": "table"
  },
  {
    "Id": 960201,
    "key": "gst",
    "label": "GST 3.00%",
    "placeholder": "",
    "priority": 1,
    "type": "checkbox",
    "visibility": "ReadWrite",
    "place": "bottom"
  },
  {
    "Id": 960301,
    "key": "edit",
    "label": "Edit",
    "placeholder": "",
    "priority": 1,
    "type": "action",
    "visibility": "ReadWrite",
    "place": "action"
  },
  {
    "Id": 960302,
    "key": "delete",
    "label": "Delete",
    "placeholder": "",
    "priority": 2,
    "type": "action",
    "visibility": "ReadWrite",
    "place": "action"
  },
  {
    "Id": 960303,
    "key": "print",
    "label": "Print",
    "placeholder": "",
    "priority": 3,
    "type": "action",
    "visibility": "ReadWrite",
    "place": "action"
  }
]
```

List column `branch` header form ke `branch` control se aata hai (`place: dialog`). Alag key nahi hai.
