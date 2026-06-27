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
| Address có ở **cả** config lẫn state | no change (hoặc update nếu thuộc tính khác) |
| Address có trong **state**, mất trong config | **destroy** |
| Address có trong **config**, chưa có trong state | **create** |

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

Dùng `for_each` để address ra đúng dạng `module.iam["app1"]` như trong sách:

```hcl
module "iam" {
  for_each = {
    app1 = [file("${path.module}/policies/app1.json")]
    app2 = [file("${path.module}/policies/app2.json")]
  }

  source   = "./modules/iam"
  name     = each.key
  policies = each.value
}

resource "local_file" "credentials" {
  filename        = "credentials"
  file_permission = "0644"
  content         = <<-EOF
    ${module.iam["app1"].credentials}
    ${module.iam["app2"].credentials}
  EOF
}
```

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
