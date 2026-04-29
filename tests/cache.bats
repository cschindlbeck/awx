#!/usr/bin/env bats

@test "awx eks list returns cached clusters without AWS call" {
  local tmpdir
  tmpdir="$(mktemp -d)"

  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  local aws_called_file="${tmpdir}/aws_eks_called"

  # Mock aws: record if eks list-clusters is called
  cat >mock/bin/aws <<EOM
#!/bin/bash
if [[ "\$*" == *eks\ list-clusters* ]]; then
  echo "1" >"${aws_called_file}"
  echo '{ "clusters": ["from-api"] }'
elif [[ "\$*" == configure* ]]; then
  echo "eu-central-1"
else
  echo '{ "clusters": ["from-api"] }'
fi
EOM
  chmod +x mock/bin/aws

  echo -e "#!/bin/bash\ncat" >mock/bin/jq
  chmod +x mock/bin/jq

  # Populate a fresh cache file
  export AWX_CACHE_DIR="${tmpdir}/cache"
  mkdir -p "$AWX_CACHE_DIR"
  echo '{ "clusters": ["from-cache"] }' >"${AWX_CACHE_DIR}/clusters_valid_profile.json"

  export AWX_CACHE_TTL=999999 # effectively never expires
  export AWS_PROFILE="valid_profile"

  run ./awx eks list

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "from-cache" ]]
  # AWS must NOT have been called for EKS list-clusters
  [[ ! -f "$aws_called_file" ]]

  rm -rf mock "$tmpdir"
}

@test "awx eks list calls AWS when cache is missing" {
  local tmpdir
  tmpdir="$(mktemp -d)"

  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  local aws_called_file="${tmpdir}/aws_eks_called"

  # Mock aws: record if eks list-clusters is called
  cat >mock/bin/aws <<EOM
#!/bin/bash
if [[ "\$*" == *eks\ list-clusters* ]]; then
  echo "1" >"${aws_called_file}"
  echo '{ "clusters": ["from-api"] }'
elif [[ "\$*" == configure* ]]; then
  echo "eu-central-1"
else
  echo '{ "clusters": ["from-api"] }'
fi
EOM
  chmod +x mock/bin/aws

  echo -e "#!/bin/bash\ncat" >mock/bin/jq
  chmod +x mock/bin/jq

  # Point to an empty cache directory — no cache file present
  export AWX_CACHE_DIR="${tmpdir}/cache"
  export AWX_CACHE_TTL=5
  export AWS_PROFILE="valid_profile"

  run ./awx eks list

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "from-api" ]]
  # AWS must have been called
  [[ -f "$aws_called_file" ]]

  rm -rf mock "$tmpdir"
}

@test "awx eks list calls AWS when cache is expired" {
  local tmpdir
  tmpdir="$(mktemp -d)"

  mkdir -p mock/bin
  export PATH="$(pwd)/mock/bin:$PATH"

  local aws_called_file="${tmpdir}/aws_eks_called"

  # Mock aws: record if eks list-clusters is called
  cat >mock/bin/aws <<EOM
#!/bin/bash
if [[ "\$*" == *eks\ list-clusters* ]]; then
  echo "1" >"${aws_called_file}"
  echo '{ "clusters": ["from-api"] }'
elif [[ "\$*" == configure* ]]; then
  echo "eu-central-1"
else
  echo '{ "clusters": ["from-api"] }'
fi
EOM
  chmod +x mock/bin/aws

  echo -e "#!/bin/bash\ncat" >mock/bin/jq
  chmod +x mock/bin/jq

  # Create a stale cache file (set mtime far in the past)
  export AWX_CACHE_DIR="${tmpdir}/cache"
  mkdir -p "$AWX_CACHE_DIR"
  echo '{ "clusters": ["from-stale-cache"] }' >"${AWX_CACHE_DIR}/clusters_valid_profile.json"
  touch -t 202001010000 "${AWX_CACHE_DIR}/clusters_valid_profile.json"

  export AWX_CACHE_TTL=5 # 5 min TTL — file from 2020 is expired
  export AWS_PROFILE="valid_profile"

  run ./awx eks list

  [ "$status" -eq 0 ]
  [[ "${output}" =~ "from-api" ]]
  # AWS must have been called because cache was expired
  [[ -f "$aws_called_file" ]]

  rm -rf mock "$tmpdir"
}
