#!/bin/bash

# 配置区域（用户可根据需要修改）
GITHUB_TOKEN=""          # GitHub访问令牌
SOCKS5_PROXY="192.168.2.7:7890" # SOCKS5代理地址
MAX_RETRY=3              # 最大重试次数
DOWNLOAD_DIR="/root/githubbak" # 下载存储目录
LOG_DIR="/root/githubbak/logs"         # 日志存储目录
PROJECT_LIST=("xifangczy/cat-catch" "vaxilu/soga") # 要监控的GitHub项目列表
MIRROR_SITE="https://www.ghproxy.cn/" # 镜像站地址（示例）

# 脚本内部变量
CURL_CMD="curl -sLf"     # 基础curl命令（代理参数动态添加）
SIMPLE_LOG="$LOG_DIR/update.log"
DETAIL_LOG="$LOG_DIR/detailed.log"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# 检查jq依赖
if ! command -v jq &>/dev/null; then
  echo "错误：jq 工具未安装，请先安装 jq。"
  exit 1
fi

# 创建必要目录
mkdir -p "$DOWNLOAD_DIR" "$LOG_DIR" "$TMP_DIR"

# 设置输出重定向
exec > >(tee -a "$DETAIL_LOG") 2>&1

# 检测代理可用性
check_proxy() {
  local proxy=$1
  $CURL_CMD --socks5 "$proxy" --connect-timeout 5 -o /dev/null https://google.com
  return $?
}

# 带分级重试的下载函数
download_with_retry() {
  local url=$1 dest=$2 retry=0
  until [ $retry -ge $MAX_RETRY ]; do
    local attempt=0
    echo "开始第 $((retry+1)) 轮重试（共 $MAX_RETRY 轮）"

    # 阶段1: 尝试代理下载
    ((attempt++))
    echo "尝试代理下载（第 ${attempt} 种方式）"
    if check_proxy "$SOCKS5_PROXY"; then
      if $CURL_CMD --socks5 "$SOCKS5_PROXY" -o "$dest" "$url"; then
        echo "代理下载成功"
        return 0
      fi
      echo "代理下载失败"
    else
      echo "代理不可用，跳过"
    fi

    # 阶段2: 尝试镜像站下载（如果配置）
    if [ -n "$MIRROR_SITE" ]; then
      ((attempt++))
      local mirror_url="${MIRROR_SITE}${url}"
      echo "尝试镜像下载（第 ${attempt} 种方式）：$mirror_url"
      if $CURL_CMD -o "$dest" "$mirror_url"; then
        echo "镜像下载成功"
        return 0
      fi
      echo "镜像下载失败"
    fi

    # 阶段3: 最后尝试直连下载
    ((attempt++))
    echo "尝试直连下载（第 ${attempt} 种方式）"
    if $CURL_CMD -o "$dest" "$url"; then
      echo "直连下载成功"
      return 0
    fi
    echo "直连下载失败"

    # 本轮所有方式均失败
    ((retry++))
    echo "本轮所有下载方式均失败，等待重试（剩余重试次数：$((MAX_RETRY - retry))）"
    sleep $((retry * 2))
  done

  echo "错误: 经过 $MAX_RETRY 轮重试仍下载失败 - $url"
  return 1
}

# 记录简单日志
log_simple() {
  local message=$1
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$SIMPLE_LOG"
}

# 主处理函数
process_release() {
  local project=$1
  local safe_project=${project//\//-}  # 将斜杠转换为连字符
  local owner=$(cut -d/ -f1 <<< "$project")
  local repo=$(cut -d/ -f2 <<< "$project")
  local api_url="https://api.github.com/repos/$owner/$repo/releases?per_page=1"
  
  # 设置认证头
  local auth_header=()
  [ -n "$GITHUB_TOKEN" ] && auth_header=(-H "Authorization: Bearer $GITHUB_TOKEN")

  # 动态构建curl命令
  local curl_cmd="$CURL_CMD"
  if check_proxy "$SOCKS5_PROXY"; then
    curl_cmd="$curl_cmd --socks5 $SOCKS5_PROXY"
    echo "使用代理访问API: $project"
  else
    echo "警告: 使用直连访问API: $project"
  fi

  # 获取发布信息
  local response
  if ! response=$($curl_cmd "${auth_header[@]}" "$api_url"); then
    echo "错误: 无法获取发布信息 - $project"
    return 1
  fi

  # 检查是否有有效发布
  if [ "$(jq 'length' <<< "$response")" -eq 0 ]; then
    echo "项目没有可用的发布版本 - $project"
    return 0
  fi

  # 解析最新发布（无论是否预发布）
  local release_data=$(jq '.[0]' <<< "$response")
  local tag_name=$(jq -r '.tag_name' <<< "$release_data") || { echo "JSON解析失败"; return 1; }
  local body=$(jq -r '.body' <<< "$release_data")
  local assets=($(jq -r '.assets[] | select(.browser_download_url) | .browser_download_url' <<< "$release_data"))

  # 检查本地版本
  local project_dir="$DOWNLOAD_DIR/$safe_project"
  local version_dir="$project_dir/$tag_name"
  
  if [ -d "$version_dir" ]; then
    echo "信息: 版本已存在 - $tag_name，跳过下载"
    return 0
  fi

  # 创建版本目录
  if ! mkdir -p "$version_dir"; then
    echo "错误: 无法创建目录 $version_dir"
    return 1
  fi

  # 写入更新详情（带错误处理）
  if ! echo "$body" > "$version_dir/updetail.txt"; then
    echo "错误: 无法写入更新详情"
    rm -rf "$version_dir"
    return 1
  fi

  # 下载所有资源
  for asset_url in "${assets[@]}"; do
    local filename=$(basename "$asset_url")
    echo "开始下载: $filename"
    
    if download_with_retry "$asset_url" "$version_dir/$filename"; then
      echo "下载成功: $filename"
    else
      echo "错误: 下载失败 - $filename"
      rm -rf "$version_dir"
      return 1
    fi
  done

  log_simple "更新项目: $project - 版本: $tag_name"
}

# 主程序
main() {
  # 初始代理检测
  if check_proxy "$SOCKS5_PROXY"; then
    echo "初始代理检测成功，后续请求将自动切换连接方式"
  else
    echo "初始代理检测失败，后续请求将自动使用镜像站/直连"
  fi

  # 处理所有项目
  for project in "${PROJECT_LIST[@]}"; do
    echo "正在处理项目: $project"
    if process_release "$project"; then
      echo "项目处理成功: $project"
    else
      echo "错误: 项目处理失败 - $project"
    fi
    echo "--------------------------------------"
  done
}

# 执行主程序
main