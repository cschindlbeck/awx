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

@test "_detect_provider auto-detects azure when kubeconfig exec is kubelogin" {
  source ./awx
  unset AWX_PROVIDER
  kubectl() {
    if [[ "$*" == *"contexts[0].context.user"* ]]; then
      echo "azure-user"
      return 0
    fi
    if [[ "$*" == *"users[?("* ]]; then
      echo "kubelogin"
      return 0
    fi
    return 1
  }
  export -f kubectl
  result="$(_detect_provider)"
  [ "$result" = "azure" ]
}

@test "_detect_provider auto-detects aws when kubeconfig exec is aws" {
  source ./awx
  unset AWX_PROVIDER
  kubectl() {
    if [[ "$*" == *"contexts[0].context.user"* ]]; then
      echo "aws-user"
      return 0
    fi
    if [[ "$*" == *"users[?("* ]]; then
      echo "aws"
      return 0
    fi
    return 1
  }
  export -f kubectl
  result="$(_detect_provider)"
  [ "$result" = "aws" ]
}

@test "_detect_provider defaults to aws when kubectl is absent" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  source ./awx
  unset AWX_PROVIDER
  result="$(PATH="$tmpdir" _detect_provider 2>/dev/null)"
  rm -rf "$tmpdir"
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
