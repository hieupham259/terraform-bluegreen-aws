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

module "iam" { #A
  source   = "./modules/iam"
  for_each = local.policy_mapping
  name     = each.key
  policies = each.value.policies
}

resource "local_file" "credentials" {
  filename = "credentials"
  content  = join("\n", [for m in module.iam : m.credentials])
}
