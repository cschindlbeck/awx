#!/usr/bin/env bats

@test "SSO profile: valid session authenticated without re-login" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"sso_start_url"* ]]; then
  echo "https://my-sso.awsapps.com/start"
elif [[ "$*" == *"aws_access_key_id"* ]]; then
  exit 1
elif [[ "$*" == configure* ]]; then
  echo "eu-central-1"
elif [[ "$*" == sts* ]]; then
  echo '{"UserId":"AIDEXAMPLE","Account":"123456789","Arn":"arn:aws:iam::123456789:user/test"}'
else
  echo '{"clusters":["cluster-sso"]}'
fi
EOM
  chmod +x mock/bin/aws

  echo -e "#!/bin/bash\ncat" >mock/bin/jq
  chmod +x mock/bin/jq
  echo -e "#!/bin/bash\necho mock-cluster" >mock/bin/fzf
  chmod +x mock/bin/fzf

  export AWS_PROFILE="sso-profile"

  run ./awx eks list 2>&1

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "cluster-sso" ]]

  # Cleanup
  rm -rf mock
}

@test "static credential profile: authenticated without SSO login" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"sso_start_url"* ]]; then
  exit 1
elif [[ "$*" == *"aws_access_key_id"* ]]; then
  echo "AKIAIOSFODNN7EXAMPLE"
elif [[ "$*" == configure* ]]; then
  echo "eu-central-1"
elif [[ "$*" == sso* ]]; then
  echo "SSO login triggered" >&2
  exit 1
elif [[ "$*" == sts* ]]; then
  echo '{"UserId":"AIDEXAMPLE","Account":"123456789","Arn":"arn:aws:iam::123456789:user/test"}'
else
  echo '{"clusters":["cluster-static"]}'
fi
EOM
  chmod +x mock/bin/aws

  echo -e "#!/bin/bash\ncat" >mock/bin/jq
  chmod +x mock/bin/jq
  echo -e "#!/bin/bash\necho mock-cluster" >mock/bin/fzf
  chmod +x mock/bin/fzf

  export AWS_PROFILE="static-profile"

  run ./awx eks list 2>&1

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "cluster-static" ]]
  [[ "${output}" =~ "Using static credentials" ]]
  # SSO login must NOT be triggered for a static-only profile
  [[ ! "${output}" =~ "SSO login triggered" ]]

  # Cleanup
  rm -rf mock
}

@test "SSO failure falls back to static credentials" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"sso_start_url"* ]]; then
  echo "https://my-sso.awsapps.com/start"
elif [[ "$*" == *"aws_access_key_id"* ]]; then
  echo "AKIAIOSFODNN7EXAMPLE"
elif [[ "$*" == configure* ]]; then
  echo "eu-central-1"
elif [[ "$*" == sts* ]]; then
  exit 1
elif [[ "$*" == sso* ]]; then
  exit 0
else
  echo '{"clusters":["cluster-fallback"]}'
fi
EOM
  chmod +x mock/bin/aws

  echo -e "#!/bin/bash\ncat" >mock/bin/jq
  chmod +x mock/bin/jq
  echo -e "#!/bin/bash\necho mock-cluster" >mock/bin/fzf
  chmod +x mock/bin/fzf

  export AWS_PROFILE="sso-static-profile"
  export AWX_STS_RETRIES=1

  run ./awx eks list 2>&1

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "cluster-fallback" ]]
  [[ "${output}" =~ "SSO failed, falling back to static credentials" ]]

  # Cleanup
  rm -rf mock
}

@test "profile with no SSO and no static credentials fails with clear error" {
  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  cat >mock/bin/aws <<'EOM'
#!/bin/bash
if [[ "$*" == *"sso_start_url"* ]]; then
  exit 1
elif [[ "$*" == *"aws_access_key_id"* ]]; then
  exit 1
elif [[ "$*" == configure* ]]; then
  echo "eu-central-1"
else
  exit 1
fi
EOM
  chmod +x mock/bin/aws

  echo -e "#!/bin/bash\ncat" >mock/bin/jq
  chmod +x mock/bin/jq
  echo -e "#!/bin/bash\necho mock-cluster" >mock/bin/fzf
  chmod +x mock/bin/fzf

  export AWS_PROFILE="unconfigured-profile"

  run ./awx eks list 2>&1

  [ "$status" -ne 0 ]
  [[ "${output}" =~ "No valid authentication method found for profile: unconfigured-profile" ]]

  # Cleanup
  rm -rf mock
}
