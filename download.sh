#!/bin/bash

# 设置代理服务器
PROXY_ADDRESS="socks5://192.168.1.1:7890"  # 将地址和端口替换为你的 SOCKS5 代理信息

# GitHub个人访问令牌
GITHUB_TOKEN="your token"

# 指定GitHub API地址
GITHUB_API="https://api.github.com/repos/"

# 指定下载根目录
DOWNLOAD_ROOT_DIR="/root/download"

# 定义要处理的GitHub仓库名称和版本号
repo_names=("ventoy/Ventoy" "XIU2/CloudflareSpeedTest")

# 设置日志文件路径
LOG_DIR="$DOWNLOAD_ROOT_DIR/logs"
LOG_FILE="$LOG_DIR/script.log"

# 检查日志文件所在的目录是否存在，如果不存在则创建
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
fi

# 设置日志文件
exec > >(tee -a "$LOG_FILE") 2>&1

# 检查代理服务器是否可用，并将结果写入日志
if [ -n "$PROXY_ADDRESS" ]; then
    if ! timeout 5 curl -I -x "$PROXY_ADDRESS" -s "https://google.com" &>/dev/null; then
        echo "代理服务器不可用，将不使用代理连接" | tee -a "$LOG_FILE"
        PROXY_ADDRESS=""
    else
        echo "代理服务器可用" | tee -a "$LOG_FILE"
    fi
fi

# 检查网络连接是否可用，并将结果写入日志
if ! timeout 5 ping -c 1 baidu.com &>/dev/null; then
    echo "网络连接不可用" | tee -a "$LOG_FILE"
    exit 1
else
    echo "网络连接可用" | tee -a "$LOG_FILE"
fi

# 函数定义：下载文件并支持重试
download_with_retry() {
    local url="$1"
    local output_file="$2"
    local max_retries=3
    local retry_count=0

    until [ $retry_count -ge $max_retries ]; do
        if timeout 300 curl -L -o "$output_file" -x "$PROXY_ADDRESS" "$url"; then
            echo "下载文件成功: $output_file" | tee -a "$LOG_FILE"
            break
        else
            retry_count=$((retry_count + 1))
            echo "下载文件失败，正在重试 (次数: $retry_count)..." | tee -a "$LOG_FILE"
        fi
    done

    if [ $retry_count -eq $max_retries ]; then
        echo "下载文件失败达到最大重试次数，放弃: $output_file" | tee -a "$LOG_FILE"
    fi
}

# 循环遍历GitHub仓库列表
for repo_name in "${repo_names[@]}"; do
    # 获取GitHub仓库的最新版本号
    latest_version_release=$(timeout 300 curl -s -H "Authorization: token $GITHUB_TOKEN" "$GITHUB_API$repo_name/releases/latest" | jq -r ".tag_name")
    latest_version_prerelease=$(timeout 300 curl -s -H "Authorization: token $GITHUB_TOKEN" "$GITHUB_API$repo_name/releases" | jq -r '.[] | select(.prerelease == true) | .tag_name' | head -n 1)
    
    # 将仓库名中的斜杠替换为破折号，用于文件夹命名
    repo_folder_name="${repo_name/\//-}"

    # 创建下载目录（如果不存在）
    mkdir -p "$DOWNLOAD_ROOT_DIR/$repo_folder_name"

    # 创建下载目录，包括仓库名和版本号
    download_dir_release="$DOWNLOAD_ROOT_DIR/$repo_folder_name/$latest_version_release"
    download_dir_prerelease="$DOWNLOAD_ROOT_DIR/$repo_folder_name/$latest_version_prerelease"
    
    # 检查本地是否存在相同版本的 release 项目，如果存在，则跳过下载
    if [ -d "$download_dir_release" ]; then
        echo "项目 '$repo_folder_name' 版本 '$latest_version_release' 已存在于本地，跳过下载 release 版本" | tee -a "$LOG_FILE"
    else
        mkdir -p "$download_dir_release"

        # 获取最新版本的 release Source code 下载链接
        tarball_url_release=$(timeout 300 curl -s -H "Authorization: token $GITHUB_TOKEN" "$GITHUB_API$repo_name/releases/latest" | jq -r ".tarball_url")
        
        if [ -z "$tarball_url_release" ]; then
            echo "无法获取GitHub仓库 '$repo_name' 的最新 release 版本下载链接" | tee -a "$LOG_FILE"
        else
            # 下载 release Source code 文件
            download_with_retry "$tarball_url_release" "$download_dir_release/source_code.tar.gz"

            # 下载 release Release 文件
            release_assets_release=$(timeout 300 curl -s -H "Authorization: token $GITHUB_TOKEN" "$GITHUB_API$repo_name/releases/latest" | jq -r ".assets[] | .name, .browser_download_url")

            if [ -z "$release_assets_release" ]; then
                echo "无法获取GitHub仓库 '$repo_name' 最新 release 版本的 Release 文件列表" | tee -a "$LOG_FILE"
            else
                IFS=$'\n'
                asset_arr_release=($release_assets_release)
                unset IFS

                for ((i = 0; i < ${#asset_arr_release[@]}; i += 2)); do
                    asset_name_release="${asset_arr_release[$i]}"
                    asset_url_release="${asset_arr_release[$i + 1]}"

                    download_with_retry "$asset_url_release" "$download_dir_release/$asset_name_release"
                done
            fi
        fi
    fi
    
    # 检查本地是否存在相同版本的 prerelease 项目，如果存在，则跳过下载
    if [ -d "$download_dir_prerelease" ]; then
        echo "项目 '$repo_folder_name' 版本 '$latest_version_prerelease' 已存在于本地，跳过下载 prerelease 版本" | tee -a "$LOG_FILE"
    else
        mkdir -p "$download_dir_prerelease"

        # 获取最新版本的 prerelease Source code 下载链接
        tarball_url_prerelease=$(timeout 300 curl -s -H "Authorization: token $GITHUB_TOKEN" "$GITHUB_API$repo_name/releases/tags/$latest_version_prerelease" | jq -r ".tarball_url")
        
        if [ -z "$tarball_url_prerelease" ]; then
            echo "无法获取GitHub仓库 '$repo_name' 的最新 prerelease 版本下载链接" | tee -a "$LOG_FILE"
        else
            # 下载 prerelease Source code 文件
            download_with_retry "$tarball_url_prerelease" "$download_dir_prerelease/source_code.tar.gz"

            # 下载 prerelease Release 文件
            release_assets_prerelease=$(timeout 300 curl -s -H "Authorization: token $GITHUB_TOKEN" "$GITHUB_API$repo_name/releases/tags/$latest_version_prerelease" | jq -r ".assets[] | .name, .browser_download_url")

            if [ -z "$release_assets_prerelease" ]; then
                echo "无法获取GitHub仓库 '$repo_name' 最新 prerelease 版本的 Release 文件列表" | tee -a "$LOG_FILE"
            else
                IFS=$'\n'
                asset_arr_prerelease=($release_assets_prerelease)
                unset IFS

                for ((i = 0; i < ${#asset_arr_prerelease[@]}; i += 2)); do
                    asset_name_prerelease="${asset_arr_prerelease[$i]}"
                    asset_url_prerelease="${asset_arr_prerelease[$i + 1]}"

                    download_with_retry "$asset_url_prerelease" "$download_dir_prerelease/$asset_name_prerelease"
                done
            fi
        fi
    fi

    # 获取并存储当前版本的更新日志
    release_notes_url_release="$GITHUB_API$repo_name/releases/latest"
    release_notes_url_prerelease="$GITHUB_API$repo_name/releases/tags/$latest_version_prerelease"
    
    release_notes_file_release="$download_dir_release/release_notes.txt"
    release_notes_file_prerelease="$download_dir_prerelease/release_notes.txt"

    if [ -n "$GITHUB_TOKEN" ]; then
        # 如果有GitHub Token，可以获取更新日志
        release_notes_release=$(timeout 300 curl -s -H "Authorization: token $GITHUB_TOKEN" "$release_notes_url_release" | jq -r ".body")
        release_notes_prerelease=$(timeout 300 curl -s -H "Authorization: token $GITHUB_TOKEN" "$release_notes_url_prerelease" | jq -r ".body")

        # 检查更新日志文件是否已存在，如果不存在才写入文件
        if [ ! -f "$release_notes_file_release" ]; then
            echo "$release_notes_release" > "$release_notes_file_release"
            echo "保存项目 '$repo_folder_name' 最新 release 版本 '$latest_version_release' 的更新日志到 '$release_notes_file_release'" | tee -a "$LOG_FILE"
        fi

        if [ ! -f "$release_notes_file_prerelease" ]; then
            echo "$release_notes_prerelease" > "$release_notes_file_prerelease"
            echo "保存项目 '$repo_folder_name' 最新 prerelease 版本 '$latest_version_prerelease' 的更新日志到 '$release_notes_file_prerelease'" | tee -a "$LOG_FILE"
        fi
    else
        echo "未提供GitHub Token，无法获取更新日志" | tee -a "$LOG_FILE"
    fi
done

echo "脚本执行完成" | tee -a "$LOG_FILE"
