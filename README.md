github项目防跑路脚本

应用场景：某些有趣的项目可能由于各种原因删库跑路，本脚本可定时更新并下载你所指定的github项目的release到本地，完全解放双手。仅在检查到有更新时下载。

主要功能是批量下载 GitHub 上的项目到本地，并在下载后检查是否为最新版本。该脚本支持代理设置，如果代理不可用则不使用代理。

在下载过程中，该脚本会记录下载日志，并将所有更新信息记录到日志文件中。github项目更新日志单独存放于相应文件夹。

下载后，该脚本会检查已下载的文件的版本，如果版本不是最新的，该脚本将会下载新版本。

使用时需配合crontab等进行定时执行

注意：

1.如果你短时间内请求过多次，可能触发ratelimit。所以建议间隔一小时以上。没放api token ，因为没有需求。需要可以自己加。

2.关于代理，可以不用管，目的是为了防止国内用户上不去github。当然你也可以用ghproxy，自己改一下就能用了。

3.因为脚本是ai写的，所以可能有一些奇怪的写法，如果恰好你发现了，请自己改一下。

update：2023.2.3 只进行一次api调用，尽量避免rate limit。
