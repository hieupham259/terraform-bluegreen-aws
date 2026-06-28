# Refactor & State: tại sao đổi file thì "no change" còn đưa vào module lại destroy/recreate

> Ghi chú cho Chapter 10 ("Testing and refactoring") — Terraform in Action.
> Giải thích vì sao việc refactor từ part 1 sang part 2 trong sách lại sinh ra
> `Plan: 9 to add, 0 to change, 7 to destroy`, và cách tái lập đúng cảnh đó.

---

## Câu hỏi

Có hai phát biểu nghe như mâu thuẫn:

1. *"Trong cùng một thư mục, Terraform gộp tất cả file `.tf` lại và làm việc với
   chúng sau khi đã gộp."* → tức là **chuyển một block resource sang file khác
   không gây thay đổi gì.**
2. Nhưng trong sách, **refactor từ part 1 sang part 2 lại khiến tài nguyên bị
   xoá đi và tạo lại** (`7 to destroy, 9 to add`).

Vậy hai điều này có chọi nhau không?

## Trả lời ngắn

**Không mâu thuẫn.** Mấu chốt nằm ở một từ:

> Terraform theo dõi mỗi resource bằng **address**, **không phải** bằng tên file.

Phát biểu (1) nói rằng *tên file không phải là address*. Còn refactor trong
sách thì *đổi chính cái address*. Hai chuyện hoàn toàn khác nhau.

---

## Address là gì

Address = danh tính mà Terraform ghi vào state để ánh xạ "khối config này ↔ tài
nguyên thật nào":

```
[đường dẫn module] . [loại resource] . [tên resource] [index]
   module.iam["app1"]  .  aws_iam_user  .     user
```

Khi chạy `plan`, Terraform so sánh **address trong config** với **address trong
state**:

| Tình huống | Kết quả |
|---|---|
| Address có ở cả config lẫn state | no change (hoặc update nếu thuộc tính khác) |
| Address có trong state, mất trong config | destroy |
| Address có trong config, chưa có trong state | create |

**Tên file KHÔNG nằm trong address.** Đó là lý do đổi file → không đổi gì.

---

## So sánh hai kiểu "refactor"

### Kiểu A — chỉ chuyển block sang file khác (cùng một module)

Address **không** đổi → `plan` báo **no change**.

```
Trước:  app1.tf  →  resource "aws_iam_user" "app1"   → address = aws_iam_user.app1
Sau:    main.tf  →  resource "aws_iam_user" "app1"   → address = aws_iam_user.app1   ✅ y hệt
```

### Kiểu B — refactor của sách (đưa vào module + đổi tên + đổi type)

Address **đổi** → `plan` báo **destroy + create**.

```
Trước:  root → resource "aws_iam_user" "app1"
        address = aws_iam_user.app1

Sau:    trong module "iam" (for_each "app1") → resource "aws_iam_user" "user"
        address = module.iam["app1"].aws_iam_user.user
```

→ State giữ `aws_iam_user.app1` (không còn trong config → **destroy**), config có
`module.iam["app1"].aws_iam_user.user` (chưa có trong state → **create**). Đây
chính là nguồn gốc của `7 to destroy, 9 to add`.

---

## Điểm tinh tế: "gộp file" chỉ áp dụng TRONG MỘT module

Quy tắc "gộp tất cả `.tf`" chỉ đúng **bên trong một module**:

- Các file ở thư mục gốc gộp lại thành **root module**.
- Các file trong `modules/iam/` gộp lại thành **child module** `iam`.

Hai module này là **hai namespace address riêng biệt**. Dù `modules/iam/` chỉ là
một thư mục con trên ổ đĩa, mọi resource trong đó đều bị gắn tiền tố
`module.iam[...]` vào address.

Vì vậy **"đưa resource vào module" không phải là "chuyển sang file khác cùng
module"** — nó là **chuyển sang một module khác**, tức đổi address.

---

## Vì sao có `moved` block

Refactor (đổi address) đúng ra không nên phá rồi dựng lại tài nguyên thật.
`moved` block là công cụ nói với Terraform: *"hai address này là cùng một tài
nguyên, chỉ cập nhật con trỏ trong state thôi, đừng destroy."*

```hcl
moved {
  from = aws_iam_user.app1
  to   = module.iam["app1"].aws_iam_user.user
}
```

Thêm các `moved` block kiểu này thì `plan` chuyển từ `9 to add, 7 to destroy`
thành `0 to add, 0 to change, 0 to destroy` (hoặc chỉ còn vài thay đổi thật sự).
Đó chính là nội dung tiếp theo của Chapter 10.

---

## Con số `9 to add / 7 to destroy` đến từ đâu

`7 to destroy` đến **100% từ file state của part 1**, không phải từ AWS. State
part 1 chứa đúng 7 resource:

| Resource trong state part 1 | Số lượng |
|---|---|
| `aws_iam_user.app1`, `aws_iam_user_policy.app1`, `aws_iam_access_key.app1` | 3 |
| `aws_iam_user.app2`, `aws_iam_user_policy.app2`, `aws_iam_access_key.app2` | 3 |
| `local_file.credentials` | 1 |
| **Tổng** | **7** |

`9 to add` đến từ config part 2 (2 module × 4 resource + `local_file` = 9):

| Resource trong config part 2 | Số lượng |
|---|---|
| `module.iam["app1"]`: `aws_iam_user.user`, `aws_iam_policy.policy[0]`, `aws_iam_user_policy_attachment.attachment[0]`, `aws_iam_access_key.access_key` | 4 |
| `module.iam["app2"]`: tương tự | 4 |
| `local_file.credentials` | 1 |
| **Tổng** | **9** |

> ⚠️ Nếu bạn **xoá file state** giữa part 1 và part 2, sẽ KHÔNG có `7 to destroy`
> (vì không còn state để biết tới 7 resource cũ) — `plan` chỉ còn `9 to add`.
> Cả Chapter 10 dựa trên giả định bạn **giữ nguyên** state của part 1.

---

## Cách tái lập đúng cảnh trong sách

Mục tiêu: chạy `terraform plan` trên part 2 và ra đúng
`Plan: 9 to add, 0 to change, 7 to destroy`.

Điều kiện bắt buộc: **state phải chứa 7 resource của part 1.** Nếu bạn đã lỡ xoá
state, hãy dựng lại theo các bước dưới.

> Lưu ý kỹ thuật: `terraform.tfstate` nằm trong thư mục làm việc và bị
> `.gitignore` — nó **dùng chung khi chuyển branch**, không thuộc về branch nào.
> Vì vậy chỉ cần apply ở part 1 rồi `git checkout part2`, state vẫn còn nguyên.

### Bước 0 — Dọn tài nguyên AWS mồ côi (nếu part 1 từng apply mà chưa destroy)

Hai IAM user `app1-svc-account` và `app2-svc-account` có thể vẫn tồn tại trên
AWS nhưng không còn được quản lý. Phải xoá trước, nếu không bước apply lại sẽ báo
`EntityAlreadyExists`. IAM user còn access key / inline policy thì AWS chặn xoá,
nên phải gỡ chúng trước:

```bash
# app1
aws iam list-access-keys --user-name app1-svc-account
aws iam delete-access-key   --user-name app1-svc-account --access-key-id <ACCESS_KEY_ID>
aws iam list-user-policies  --user-name app1-svc-account
aws iam delete-user-policy  --user-name app1-svc-account --policy-name <POLICY_NAME>
aws iam delete-user         --user-name app1-svc-account

# app2 (lặp lại tương tự)
aws iam delete-access-key   --user-name app2-svc-account --access-key-id <ACCESS_KEY_ID>
aws iam delete-user-policy  --user-name app2-svc-account --policy-name <POLICY_NAME>
aws iam delete-user         --user-name app2-svc-account
```

> Cách nhanh hơn cho môi trường học tập: xoá 2 user này qua AWS Console
> (Console tự gỡ key/policy đính kèm khi bạn xoá user).

### Bước 1 — Quay về part 1 và apply để dựng lại state

```bash
git checkout feat/chapter10-part1
terraform init        # nếu chưa init trên cây làm việc hiện tại
terraform apply        # tạo 7 resource trên AWS + sinh terraform.tfstate
```

Kiểm chứng state có đúng 7 resource:

```bash
terraform state list
# aws_iam_access_key.app1
# aws_iam_access_key.app2
# aws_iam_user.app1
# aws_iam_user.app2
# aws_iam_user_policy.app1
# aws_iam_user_policy.app2
# local_file.credentials
```

### Bước 2 — Chuyển sang part 2 (state vẫn nằm nguyên trong thư mục)

```bash
git checkout feat/chapter10-part2
```

### Bước 3 — Thêm phần gọi module vào `main.tf`

Dùng `locals` + `for_each` để address ra đúng dạng `module.iam["app1"]` như trong sách:

```hcl
locals {
  policies = {
    for path in fileset(path.module, "policies/*.json") : basename(path) => file(path)
  }
  policy_mapping = {
    "app1" = {
      policies = [local.policies["app1.json"]],
    },
    "app2" = {
      policies = [local.policies["app2.json"]],
    },
  }
}

module "iam" {
  source   = "./modules/iam"
  for_each = local.policy_mapping
  name     = each.key
  policies = each.value.policies
}

resource "local_file" "credentials" {
  filename = "credentials"
  content  = join("\n", [for m in module.iam : m.credentials])
}
```

#### Giải thích đoạn code trên

**1. `locals { policies = { for path in fileset(...) ... } }` — đọc toàn bộ file policy**

`fileset(path.module, "policies/*.json")` trả về **set** các đường dẫn khớp glob,
ví dụ: `{ "policies/app1.json", "policies/app2.json" }`.

`for path in fileset(...) : basename(path) => file(path)` là **for expression**
duyệt qua set đó và tạo một **map**:

```
policies = {
  "app1.json" = "<nội dung JSON của app1>"
  "app2.json" = "<nội dung JSON của app2>"
}
```

- `basename(path)` lấy tên file, bỏ phần thư mục (`"policies/app1.json"` → `"app1.json"`), dùng làm **key** của map.
- `file(path)` đọc nội dung file thành chuỗi JSON, dùng làm **value**.

Cách này tổng quát hơn hard-code từng file: thêm `app3.json` vào thư mục
`policies/` là nó tự được nạp, không cần sửa code.

**2. `locals { policy_mapping = { ... } }` — ánh xạ app → danh sách policy**

```hcl
policy_mapping = {
  "app1" = { policies = [local.policies["app1.json"]] }
  "app2" = { policies = [local.policies["app2.json"]] }
}
```

Đây là map **tên app → object chứa list policy**. Bọc trong `[ ... ]` để biến
chuỗi JSON thành **list 1 phần tử**, vì biến `policies` của module khai báo kiểu
`list(string)` (xem `modules/iam/variables.tf`). Muốn gắn nhiều policy cho một
app thì thêm phần tử vào list: `[local.policies["a.json"], local.policies["b.json"]]`.

Tách làm 2 local (`policies` và `policy_mapping`) thay vì gộp 1 giúp mỗi phần
có một trách nhiệm rõ: một bên đọc file, một bên khai báo mapping.

**3. `module "iam" { for_each = local.policy_mapping }` — gọi module, nhân thành nhiều bản**

Đây chính là block còn thiếu khiến trước đó `plan` báo "no changes": file trong
`modules/iam/` chỉ có hiệu lực khi có một block `module` trỏ tới nó.

`for_each` nhận map `local.policy_mapping`. Terraform tạo **một instance module
cho mỗi key**:

| Key trong map | Instance address |
|---|---|
| `"app1"` | `module.iam["app1"]` |
| `"app2"` | `module.iam["app2"]` |

Chính `for_each` (map) tạo ra dạng address có ngoặc vuông `module.iam["app1"]`
đúng như trong sách. (Nếu dùng `count` thì address sẽ là `module.iam[0]`; nếu
gọi 2 module riêng `module "app1"` / `module "app2"` thì address là
`module.app1` — đều **không** khớp sách.)

**4. `name = each.key` và `policies = each.value.policies` — truyền biến vào module**

Trong vòng lặp `for_each`, với mỗi iteration:
- `each.key` = tên app (`"app1"` hoặc `"app2"`).
- `each.value` = object `{ policies = [...] }`.
- `each.value.policies` = list chuỗi JSON policy.

| Biến module | Giá trị truyền vào (app1) | Module dùng để... |
|---|---|---|
| `name` (string) | `"app1"` | đặt tên user: `"${var.name}-svc-account"` → `app1-svc-account` |
| `policies` (list(string)) | `["<nội dung app1.json>"]` | tạo `aws_iam_policy` với `count = length(var.policies)` |

Nhờ `each.key = "app1"`, user vẫn mang đúng tên `app1-svc-account` như part 1.

**5. `resource "local_file" "credentials"` — ghi file credentials**

```hcl
content = join("\n", [for m in module.iam : m.credentials])
```

- `module.iam` khi dùng `for_each` là một **map** các instance: `{ "app1" = <object>, "app2" = <object> }`.
- `[for m in module.iam : m.credentials]` duyệt qua map đó, lấy **output `credentials`** của từng instance, tạo thành list chuỗi.
- `join("\n", [...])` nối các chuỗi lại bằng ký tự xuống dòng thành nội dung file cuối cùng.

Cách này tổng quát hơn hard-code `module.iam["app1"].credentials` + `module.iam["app2"].credentials`: thêm app mới vào `policy_mapping` là file `credentials` tự có thêm section, không cần sửa `local_file`.

> Tóm lại: `locals` đọc file policy và khai báo mapping; block `module` "bật"
> module IAM và nhân nó thành N bản qua `for_each`; `local_file` gom output của
> tất cả bản lại thành file `credentials` mà không cần liệt kê từng app.

### Bước 4 — Plan và đối chiếu với sách

```bash
terraform init        # cần init lại vì vừa thêm module mới
terraform plan
```

Kết quả mong đợi:

```
Plan: 9 to add, 0 to change, 7 to destroy.
```

→ Khớp với hình trong sách. Từ đây mới làm tiếp được phần dùng `moved` block để
biến `7 to destroy` thành `0 to destroy`.

### Bước 5 (phần tiếp theo của sách) — Migrate state bằng `moved`

Thêm các `moved` block để Terraform hiểu đây là cùng tài nguyên, chỉ đổi address:

```hcl
moved {
  from = aws_iam_user.app1
  to   = module.iam["app1"].aws_iam_user.user
}

moved {
  from = aws_iam_user.app2
  to   = module.iam["app2"].aws_iam_user.user
}

# ... thêm moved cho access_key, v.v. tuỳ phần sách muốn giữ lại.
```

Sách lưu ý: chỉ migrate những resource quan trọng (ví dụ IAM user — vì gắn với
CloudWatch logs), còn IAM policy / access key thì bỏ qua vì tạo lại không mất mát
gì. Sau khi thêm `moved`, chạy lại `terraform plan` để thấy số `to destroy` giảm
xuống.

---

## Tóm tắt một dòng

Terraform quan tâm tới **address**, không quan tâm tới **tên file**. Đổi file →
address giữ nguyên → no change. Đưa vào module → address đổi → destroy + create.
`moved` block là cách đổi address mà không phá tài nguyên. Và đừng bao giờ xoá
file state giữa part 1 và part 2 — đó chính là cái Chapter 10 muốn bạn migrate.
