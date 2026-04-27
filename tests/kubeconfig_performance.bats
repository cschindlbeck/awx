#!/usr/bin/env bats

setup() {
  CALL_LOG="$(mktemp)"
  export CALL_LOG
  export DEFAULT_REGION="eu-central-1"
  export AWS_PROFILE="test-profile"
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  # Mock aws: capture update-kubeconfig calls; return success for STS and configure
  cat >mock/bin/aws <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"update-kubeconfig"* ]]; then
  echo "called" >>"$CALL_LOG"
elif [[ "$*" == configure* ]]; then
  echo "eu-central-1"
else
  echo '{"UserId":"TEST","Account":"123456789","Arn":"arn:aws:iam::123456789:user/test"}'
fi
EOF
  chmod +x mock/bin/aws

  # fzf and jq stubs (not invoked by _eks_ensure_kubeconfig directly, but needed for sourcing)
  printf '#!/usr/bin/env bash\nexit 0\n' >mock/bin/fzf
  printf '#!/usr/bin/env bash\ncat\n' >mock/bin/jq
  chmod +x mock/bin/fzf mock/bin/jq
}

teardown() {
  rm -f "$CALL_LOG"
  rm -rf mock
}

@test "_eks_ensure_kubeconfig skips update when context already matches cluster" {
  # kubectl returns ARN whose suffix matches the cluster name
  cat >mock/bin/kubectl <<'EOF'
#!/usr/bin/env bash
echo "arn:aws:eks:eu-central-1:123456789:cluster/test-cluster"
EOF
  chmod +x mock/bin/kubectl

  source ./awx

  run _eks_ensure_kubeconfig "test-profile" "test-cluster" "eu-central-1"

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "already up-to-date" ]]
  [ ! -s "$CALL_LOG" ]  # update-kubeconfig must NOT have been called
}

@test "_eks_ensure_kubeconfig runs update when context exists but points to a different cluster" {
  # kubectl returns ARN for a DIFFERENT cluster
  cat >mock/bin/kubectl <<'EOF'
#!/usr/bin/env bash
echo "arn:aws:eks:eu-central-1:123456789:cluster/other-cluster"
EOF
  chmod +x mock/bin/kubectl

  source ./awx

  run _eks_ensure_kubeconfig "test-profile" "test-cluster" "eu-central-1"

  [ "$status" -eq 0 ]
  [ -s "$CALL_LOG" ]  # update-kubeconfig MUST have been called
}

@test "_eks_ensure_kubeconfig runs update when context does not exist" {
  # kubectl returns empty (context not found)
  cat >mock/bin/kubectl <<'EOF'
#!/usr/bin/env bash
echo ""
EOF
  chmod +x mock/bin/kubectl

  source ./awx

  run _eks_ensure_kubeconfig "test-profile" "test-cluster" "eu-central-1"

  [ "$status" -eq 0 ]
  [ -s "$CALL_LOG" ]  # update-kubeconfig MUST have been called
}

@test "_eks_ensure_kubeconfig --force bypasses skip even when context already matches" {
  # kubectl returns matching ARN — but --force should still trigger the update
  cat >mock/bin/kubectl <<'EOF'
#!/usr/bin/env bash
echo "arn:aws:eks:eu-central-1:123456789:cluster/test-cluster"
EOF
  chmod +x mock/bin/kubectl

  source ./awx

  run _eks_ensure_kubeconfig "test-profile" "test-cluster" "eu-central-1" "--force"

  [ "$status" -eq 0 ]
  [ -s "$CALL_LOG" ]  # update-kubeconfig MUST have been called despite match
}

@test "_eks_ensure_kubeconfig warns and runs update when kubectl is not available" {
  # No kubectl in mock/bin — ensure it is absent from PATH mock
  # (mock/bin/kubectl deliberately not created)

  source ./awx

  run _eks_ensure_kubeconfig "test-profile" "test-cluster" "eu-central-1" 2>&1

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "kubectl" ]]  # warn message must mention kubectl
  [ -s "$CALL_LOG" ]              # update-kubeconfig MUST have been called as fallback
}
