#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$(cd "${script_dir}/.." && pwd)"
source_skill_dir="${package_dir}/skills/codex-desktop-pet"
codex_home="${CODEX_HOME:-${HOME}/.codex}"
target_dir="${codex_home}/skills/codex-desktop-pet"

if [[ ! -f "${source_skill_dir}/SKILL.md" ]]; then
  echo "未找到 skill 文件：${source_skill_dir}/SKILL.md" >&2
  echo "请从完整 release zip 解压后，在包目录内运行 Scripts/install-codex-skill.sh。" >&2
  exit 1
fi

mkdir -p "${codex_home}/skills"
rm -rf "${target_dir}"
cp -R "${source_skill_dir}" "${target_dir}"

echo "已安装 Codex skill：${target_dir}"
echo "重启 Codex 或开启新会话后，Codex 会在任务进度和完成时上报给 Whisky&Cling。"
