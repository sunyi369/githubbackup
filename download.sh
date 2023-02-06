#!/bin/bash
#要下载的项目，不够自己加
repo_names=("aria2/aria2" "aria2/aria2")
#下载路径
download_path="/root"
echo 下载路径为$download_path
mkdir -p $download_path
echo 建立下载目录$download_path
#定义代理判断代理是否能用，自己改
proxy="192.168.1.255:7890"
curl --connect-timeout 3 --socks5 $proxy http://www.google.com/ &> /dev/null
if [ $? -eq 0 ]
then
 echo "$(date) - 代理ok"
 echo "$(date) - 代理ok" >> $download_path/update.log
 export http_proxy=socks5://$proxy
 export https_proxy=socks5://$proxy
else
  echo "$(date) - 代理歇菜,不设置代理"
  echo "$(date) - 代理歇菜,不设置代理" >> $download_path/update.log
 export http_proxy=""
 export https_proxy=""
fi

for repo_name in ${repo_names[@]}; do
  echo 当前下载项目为$repo_name
  # 获取最新版本的发布信息
  release_info=$(curl -s https://api.github.com/repos/$repo_name/releases/latest)
  current_version=$(echo "$release_info" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  name1="${repo_name%/*}"
  name2="${repo_name#*/}"
  echo  获取项目版本为$current_version

  version_file="$download_path/$name1-$name2/$name2-ver.txt"
  dir_name="$download_path/$name1-$name2/$name2-ver$current_version/"
  echo  创建文件夹$dir_name
  mkdir -p $dir_name
  echo "查找$name2更新"
  touch $version_file
  if [ -f $version_file ]; then
      stored_version=$(cat $version_file)
      if [ "$current_version" == "$stored_version" ]; then
          echo "$(date) - $name2 没有更新" >> $download_path/update.log
          echo "$(date) - $name2 没有更新"
           continue
      fi
  fi
  

  # 从发布信息中提取更新日志
  update_log=$(echo "$release_info" | sed -n 's/.*"body": "\(.*\)".*/\1/p')
  # 打印更新日志
  echo "$name2-ver$current_version$update_log" >> $dir_name/updatedetail.log
  echo "$name2-ver$current_version$update_log" >> $download_path/Allupdatedetail.log

  assets_url=$(echo "$release_info" | grep '"assets_url"' | sed -E 's/.*"assets_url": "([^"]+)".*/\1/')
  echo 最新版本的资源集合为$assets_url

  for asset_url in $(curl -s $assets_url | grep '"browser_download_url":' | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/'); do
  echo $(basename $asset_url)下载地址为$asset_url
  echo "文件下载到 $dir_name$(basename $asset_url)"
  #curl -sLJO $asset_url -o "$download_path/$name1/$name1-$current_version/"
  #wget -P "$download_path/$name1/$name1-$current_version/" $asset_url
  cd $dir_name && { curl -JLO --progress-bar $asset_url ; cd -; }
  done

  echo 更新$name2的版本号为$current_version
  echo $current_version > $version_file
  echo "$(date) - $name2 更新到版本 $current_version" >> $download_path/update.log
done
