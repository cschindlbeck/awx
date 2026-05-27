#!/usr/bin/env bats

setup() {
  unset AWX_PROVIDER
  rm -rf mock
  KUBELOGIN_CALL_FILE="$BATS_TMPDIR/last_kubelogin_call"
  KUBELOGIN_DEFAULT_CALL_FILE="$BATS_TMPDIR/last_kubelogin_call_default"
  rm -f "$KUBELOGIN_CALL_FILE" "$KUBELOGIN_DEFAULT_CALL_FILE"
}

teardown() {
  unset AWX_PROVIDER
  rm -rf mock
  rm -f "$KUBELOGIN_CALL_FILE" "$KUBELOGIN_DEFAULT_CALL_FILE"
}

@test "_detect_provider returns azure when AWX_PROVIDER=azure" {
  source ./awx
  AWX_PROVIDER="azure"
  result="$(_detect_provider)"
  [ "$result" = "azure" ]
}

@test "_detect_provider returns aws when AWX_PROVIDER=aws" {
  source ./awx
  AWX_PROVIDER="aws"
  result="$(_detect_provider)"
  [ "$result" = "aws" ]
}

@test "_detect_provider defaults to aws when AWX_PROVIDER is unset" {
  source ./awx
  unset AWX_PROVIDER
  result="$(_detect_provider)"
  [ "$result" = "aws" ]
}

# ---------------------------------------------------------------------------
# check_deps in Azure mode
# ---------------------------------------------------------------------------

@test "check_deps azure mode requires kubelogin" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  # PATH has kubectl and fzf but not kubelogin
  cat >"$tmpdir/kubectl" <<'EOM'
#!/bin/bash
exit 0
EOM
  cat >"$tmpdir/fzf" <<'EOM'
#!/bin/bash
exit 0
EOM
  chmod +x "$tmpdir/kubectl" "$tmpdir/fzf"

  AWX_PROVIDER="azure" PATH="$tmpdir:/usr/bin:/bin:/usr/sbin:/sbin" run ./awx use 2>&1
  [ "$status" -ne 0 ]
  [[ "${output}" =~ "Missing dependency: kubelogin" ]]
  rm -rf "$tmpdir"
}

@test "check_deps azure mode does not require aws" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  # Provide kubectl, fzf, kubelogin but NOT aws
  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
if [[ "$*" == "config get-contexts -o name" ]]; then
  echo "lynqtech-dev"
elif [[ "$*" == "config use-context"* ]]; then
  exit 0
elif [[ "$*" == *"contexts[0].context.user"* ]]; then
  echo "azure-user"
elif [[ "$*" == *"users[?("* ]]; then
  echo "kubelogin"
fi
EOM
  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
head -n1
EOM
  cat >mock/bin/kubelogin <<'EOM'
#!/bin/bash
exit 0
EOM
  chmod +x mock/bin/kubectl mock/bin/fzf mock/bin/kubelogin

  AWX_PROVIDER="azure" run ./awx use 2>&1
  [ "$status" -eq 0 ]
  [[ "${output}" != *"Missing dependency: aws"* ]]
}

# ---------------------------------------------------------------------------
# awx use in Azure mode
# ---------------------------------------------------------------------------

@test "awx use in Azure mode switches to context selected by fzf" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
if [[ "$*" == "config get-contexts -o name" ]]; then
  printf "lynqtech-dev\nlynqtech-prod\n"
elif [[ "$*" == "config use-context"* ]]; then
  exit 0
elif [[ "$*" == *"contexts[0].context.user"* ]]; then
  echo "azure-user"
elif [[ "$*" == *"users[?("* ]]; then
  echo "kubelogin"
fi
EOM
  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
head -n1
EOM
  cat >mock/bin/kubelogin <<'EOM'
#!/bin/bash
exit 0
EOM
  chmod +x mock/bin/kubectl mock/bin/fzf mock/bin/kubelogin

  AWX_PROVIDER="azure" run ./awx use 2>&1
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Switched to context: lynqtech-dev" ]]
  [[ "${output}" =~ "kubelogin authentication configured" ]]
}

@test "awx use in Azure mode auto-selects single context" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
if [[ "$*" == "config get-contexts -o name" ]]; then
  echo "lynqtech-dev"
elif [[ "$*" == "config use-context"* ]]; then
  exit 0
elif [[ "$*" == *"contexts[0].context.user"* ]]; then
  echo "azure-user"
elif [[ "$*" == *"users[?("* ]]; then
  echo "kubelogin"
fi
EOM
  # fzf must NOT be called for single-context selection
  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
echo "[ERROR] fzf called unexpectedly for single-context selection" >&2
exit 1
EOM
  cat >mock/bin/kubelogin <<'EOM'
#!/bin/bash
exit 0
EOM
  chmod +x mock/bin/kubectl mock/bin/fzf mock/bin/kubelogin

  AWX_PROVIDER="azure" run ./awx use 2>&1
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "Auto-selecting the only available context: lynqtech-dev" ]]
  [[ "${output}" != *"fzf called unexpectedly"* ]]
}

@test "awx use in Azure mode fails when no kubeconfig contexts exist" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
if [[ "$*" == "config get-contexts -o name" ]]; then
  exit 0   # empty output
elif [[ "$*" == *"contexts[0].context.user"* ]]; then
  echo "azure-user"
elif [[ "$*" == *"users[?("* ]]; then
  echo "kubelogin"
fi
EOM
  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
head -n1
EOM
  cat >mock/bin/kubelogin <<'EOM'
#!/bin/bash
exit 0
EOM
  chmod +x mock/bin/kubectl mock/bin/fzf mock/bin/kubelogin

  AWX_PROVIDER="azure" run ./awx use 2>&1
  [ "$status" -ne 0 ]
  [[ "${output}" =~ "No kubeconfig contexts found" ]]
}

@test "awx use in Azure mode passes AWX_KUBELOGIN_LOGIN_TYPE to kubelogin" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
if [[ "$*" == "config get-contexts -o name" ]]; then
  echo "lynqtech-dev"
elif [[ "$*" == "config use-context"* ]]; then
  exit 0
elif [[ "$*" == *"contexts[0].context.user"* ]]; then
  echo "azure-user"
elif [[ "$*" == *"users[?("* ]]; then
  echo "kubelogin"
fi
EOM
  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
head -n1
EOM
  cat >mock/bin/kubelogin <<EOM
#!/bin/bash
echo "kubelogin \$*" >"$KUBELOGIN_CALL_FILE"
exit 0
EOM
  chmod +x mock/bin/kubectl mock/bin/fzf mock/bin/kubelogin

  AWX_PROVIDER="azure" AWX_KUBELOGIN_LOGIN_TYPE="azurecli" run ./awx use 2>&1
  [ "$status" -eq 0 ]
  grep -q "convert-kubeconfig -l azurecli" "$KUBELOGIN_CALL_FILE"
}

@test "AWX_KUBELOGIN_LOGIN_TYPE defaults to interactive" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
if [[ "$*" == "config get-contexts -o name" ]]; then
  echo "lynqtech-dev"
elif [[ "$*" == "config use-context"* ]]; then
  exit 0
elif [[ "$*" == *"contexts[0].context.user"* ]]; then
  echo "azure-user"
elif [[ "$*" == *"users[?("* ]]; then
  echo "kubelogin"
fi
EOM
  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
head -n1
EOM
  cat >mock/bin/kubelogin <<EOM
#!/bin/bash
echo "kubelogin \$*" >"$KUBELOGIN_DEFAULT_CALL_FILE"
exit 0
EOM
  chmod +x mock/bin/kubectl mock/bin/fzf mock/bin/kubelogin

  AWX_PROVIDER="azure" run ./awx use 2>&1
  [ "$status" -eq 0 ]
  grep -q "convert-kubeconfig -l interactive" "$KUBELOGIN_DEFAULT_CALL_FILE"
}

# ---------------------------------------------------------------------------
# awx whoami in Azure mode
# ---------------------------------------------------------------------------

@test "awx whoami in Azure mode shows kubectl context info without aws" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
if [[ "$*" == "config current-context" ]]; then
  echo "lynqtech-dev"
elif [[ "$*" == "config view --minify" ]]; then
  echo "apiVersion: v1"
  echo "current-context: lynqtech-dev"
elif [[ "$*" == *"contexts[0].context.user"* ]]; then
  echo "azure-user"
elif [[ "$*" == *"users[?("* ]]; then
  echo "kubelogin"
fi
EOM
  chmod +x mock/bin/kubectl

  AWX_PROVIDER="azure" run ./awx whoami 2>&1
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "lynqtech-dev" ]]
  [[ "${output}" != *"aws"* ]]
}

# ---------------------------------------------------------------------------
# AWS-only command guards
# ---------------------------------------------------------------------------

@test "awx profiles fails with clear error in Azure mode" {
  AWX_PROVIDER="azure" run ./awx profiles 2>&1
  [ "$status" -ne 0 ]
  [[ "${output}" =~ "awx profiles is AWS-only" ]]
  [[ "${output}" =~ "kubectl config get-contexts" ]]
}

@test "awx eks list fails with clear error in Azure mode" {
  AWX_PROVIDER="azure" run ./awx eks list 2>&1
  [ "$status" -ne 0 ]
  [[ "${output}" =~ "awx eks is AWS-only" ]]
}

@test "awx logout fails with clear error in Azure mode" {
  AWX_PROVIDER="azure" run ./awx logout 2>&1
  [ "$status" -ne 0 ]
  [[ "${output}" =~ "awx logout is AWS-only" ]]
  [[ "${output}" =~ "az logout" ]]
}

@test "awx refresh fails with clear error in Azure mode" {
  AWX_PROVIDER="azure" run ./awx refresh 2>&1
  [ "$status" -ne 0 ]
  [[ "${output}" =~ "awx refresh is AWS-only" ]]
}

# ---------------------------------------------------------------------------
# awx - (prev) with Azure state
# ---------------------------------------------------------------------------

@test "awx - switches to Azure previous context" {
  export AWX_STATE_FILE
  AWX_STATE_FILE="$(mktemp)"
  rm -f "$AWX_STATE_FILE"
  export AWX_CACHE_DIR
  AWX_CACHE_DIR="$(mktemp -d)"

  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
if [[ "$*" == "config use-context"* ]]; then
  exit 0
elif [[ "$*" == *"contexts[0].context.user"* ]]; then
  echo "azure-user"
elif [[ "$*" == *"users[?("* ]]; then
  echo "kubelogin"
fi
EOM
  cat >mock/bin/kubelogin <<'EOM'
#!/bin/bash
exit 0
EOM
  chmod +x mock/bin/kubectl mock/bin/kubelogin

  # Seed state: current=aws-profile,aws-cluster  previous=azure:lynqtech-dev,
  printf "aws-profile,aws-cluster\nazure:lynqtech-dev,\n" >"$AWX_STATE_FILE"

  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx - 2>&1
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "lynqtech-dev" ]]
  [[ "${output}" =~ "kubelogin authentication configured" ]]

  rm -f "$AWX_STATE_FILE"
  rm -rf "$AWX_CACHE_DIR"
}

@test "awx - switches from Azure back to AWS" {
  export AWX_STATE_FILE
  AWX_STATE_FILE="$(mktemp)"
  rm -f "$AWX_STATE_FILE"
  export AWX_CACHE_DIR
  AWX_CACHE_DIR="$(mktemp -d)"

  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == configure* ]]; then echo "eu-central-1"
elif [[ "$*" == sts* ]]; then echo '{"UserId":"X","Account":"123","Arn":"arn"}'
elif [[ "$*" == eks\ update-kubeconfig* ]]; then exit 0
fi
EOM
  cat >mock/bin/jq <<'EOM'
#!/bin/bash
if [[ "$*" == -e* ]]; then exit 0; fi
cat
EOM
  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
if [[ "$*" == "config get-contexts -o name" ]]; then exit 0; fi
if [[ "$*" == "config use-context"* ]]; then exit 0; fi
if [[ "$*" == *"contexts[0].context.user"* ]]; then echo "aws-user"; fi
if [[ "$*" == *"users[?("* ]]; then echo "aws"; fi
EOM
  chmod +x mock/bin/aws mock/bin/jq mock/bin/kubectl

  # Seed state: current=azure:lynqtech-dev,  previous=dev-profile,dev-cluster
  printf "azure:lynqtech-dev,\ndev-profile,dev-cluster\n" >"$AWX_STATE_FILE"

  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx - 2>&1
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "dev-profile" ]]

  rm -f "$AWX_STATE_FILE"
  rm -rf "$AWX_CACHE_DIR"
}

# ---------------------------------------------------------------------------
# kubelogin auto-run in AWS flow
# ---------------------------------------------------------------------------

@test "awx use in AWS mode runs kubelogin when context uses it" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == configure* ]]; then echo "eu-central-1"
elif [[ "$*" == sts* ]]; then echo '{"UserId":"X","Account":"123","Arn":"arn"}'
elif [[ "$*" == eks\ list-clusters* ]]; then echo '{"clusters":["lynqtech-dev"]}'
elif [[ "$*" == eks\ update-kubeconfig* ]]; then exit 0
fi
EOM
  cat >mock/bin/jq <<'EOM'
#!/bin/bash
if [[ "$*" == -e* ]]; then exit 0; fi
if [[ "$*" == -r* ]]; then printf "lynqtech-dev\n"; exit 0; fi
cat
EOM
  cat >mock/bin/fzf <<'EOM'
#!/bin/bash
head -n1
EOM
  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
if [[ "$*" == "config get-contexts -o name" ]]; then exit 0; fi
if [[ "$*" == "config use-context"* ]]; then exit 0; fi
if [[ "$*" == *"contexts[0].context.user"* ]]; then echo "azure-user"; fi
if [[ "$*" == *"users[?("* ]]; then echo "kubelogin"; fi
if [[ "$*" == "config view --minify"* ]]; then echo "kubelogin"; fi
EOM
  cat >mock/bin/kubelogin <<'EOM'
#!/bin/bash
echo "kubelogin $*" >/tmp/awx_test_kubelogin_aws_flow
exit 0
EOM
  chmod +x mock/bin/aws mock/bin/jq mock/bin/fzf mock/bin/kubectl mock/bin/kubelogin

  run ./awx use --profile test-profile --cluster lynqtech-dev 2>&1
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "kubelogin authentication configured" ]]
  grep -q "convert-kubeconfig -l interactive" /tmp/awx_test_kubelogin_aws_flow
  rm -f /tmp/awx_test_kubelogin_aws_flow
}

@test "awx - in AWS mode runs kubelogin when context uses it" {
  export AWX_STATE_FILE
  AWX_STATE_FILE="$(mktemp)"
  export AWX_CACHE_DIR
  AWX_CACHE_DIR="$(mktemp -d)"

  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == configure* ]]; then echo "eu-central-1"
elif [[ "$*" == sts* ]]; then echo '{"UserId":"X","Account":"123","Arn":"arn"}'
elif [[ "$*" == eks\ update-kubeconfig* ]]; then exit 0
fi
EOM
  cat >mock/bin/jq <<'EOM'
#!/bin/bash
if [[ "$*" == -e* ]]; then exit 0; fi
cat
EOM
  cat >mock/bin/kubectl <<'EOM'
#!/bin/bash
if [[ "$*" == "config get-contexts -o name" ]]; then exit 0; fi
if [[ "$*" == "config use-context"* ]]; then exit 0; fi
if [[ "$*" == *"contexts[0].context.user"* ]]; then echo "azure-user"; fi
if [[ "$*" == *"users[?("* ]]; then echo "kubelogin"; fi
if [[ "$*" == "config view --minify"* ]]; then echo "kubelogin"; fi
EOM
  cat >mock/bin/kubelogin <<'EOM'
#!/bin/bash
echo "kubelogin $*" >/tmp/awx_test_kubelogin_prev_flow
exit 0
EOM
  chmod +x mock/bin/aws mock/bin/jq mock/bin/kubectl mock/bin/kubelogin

  # Seed state: current=azure:lynqtech-dev,  previous=dev-profile,dev-cluster
  printf "azure:lynqtech-dev,\ndev-profile,dev-cluster\n" >"$AWX_STATE_FILE"

  AWX_STATE_FILE="$AWX_STATE_FILE" run ./awx - 2>&1
  [ "$status" -eq 0 ]
  [[ "${output}" =~ "dev-profile" ]]
  [[ "${output}" =~ "kubelogin authentication configured" ]]
  grep -q "convert-kubeconfig -l interactive" /tmp/awx_test_kubelogin_prev_flow
  rm -f /tmp/awx_test_kubelogin_prev_flow

  rm -f "$AWX_STATE_FILE"
  rm -rf "$AWX_CACHE_DIR"
}

# ---------------------------------------------------------------------------
# AWS_PROFILE unset in Azure paths
# ---------------------------------------------------------------------------

@test "awx_azure_use unsets AWS_PROFILE and AWS_REGION" {
  export AWX_STATE_FILE
  AWX_STATE_FILE="$(mktemp)"
  rm -f "$AWX_STATE_FILE"

  source ./awx
  export AWS_PROFILE="old-aws-profile"
  export AWS_REGION="eu-central-1"
  export AWS_DEFAULT_REGION="eu-central-1"
  AWX_PROVIDER="azure"

  kubectl() {
    case "$*" in
      "config get-contexts -o name") echo "lynqtech-dev" ;;
      "config use-context lynqtech-dev") return 0 ;;
      "config view"*) echo "kubelogin" ;;
    esac
  }
  export -f kubectl

  kubelogin() { return 0; }
  export -f kubelogin

  awx_azure_use 2>/dev/null

  [ -z "${AWS_PROFILE:-}" ]
  [ -z "${AWS_REGION:-}" ]
  [ -z "${AWS_DEFAULT_REGION:-}" ]

  rm -f "$AWX_STATE_FILE"
}

@test "awx_prev Azure branch unsets AWS_PROFILE and AWS_REGION" {
  export AWX_STATE_FILE
  AWX_STATE_FILE="$(mktemp)"
  export AWX_CACHE_DIR
  AWX_CACHE_DIR="$(mktemp -d)"

  # Seed state: current=aws-profile,aws-cluster  previous=azure:lynqtech-dev,
  printf "aws-profile,aws-cluster\nazure:lynqtech-dev,\n" >"$AWX_STATE_FILE"

  source ./awx
  export AWS_PROFILE="aws-profile"
  export AWS_REGION="eu-central-1"
  export AWS_DEFAULT_REGION="eu-central-1"

  kubectl() {
    case "$*" in
      "config use-context lynqtech-dev") return 0 ;;
      "config view"*) echo "kubelogin" ;;
    esac
  }
  export -f kubectl

  kubelogin() { return 0; }
  export -f kubelogin

  awx_prev 2>/dev/null

  [ -z "${AWS_PROFILE:-}" ]
  [ -z "${AWS_REGION:-}" ]
  [ -z "${AWS_DEFAULT_REGION:-}" ]

  rm -f "$AWX_STATE_FILE"
  rm -rf "$AWX_CACHE_DIR"
}
