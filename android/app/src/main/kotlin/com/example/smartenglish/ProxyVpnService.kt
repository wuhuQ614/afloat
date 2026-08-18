package com.example.smartenglish

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor

/**
 * 系统级 VPN 接管骨架。
 *
 * 说明：Android 的全局流量接管需要由 VpnService 创建 TUN 接口，并把 TUN 文件描述符
 * 交给与"本进程同进程"运行的核心隧道（如 go-mobile 编译的 mihomo 原生库）使用，
 * 才能实现真正接管所有 App 流量的 TUN/VPN 模式。
 *
 * 目前 AFloat 移动端以「App 内代理」方式工作（不需要 root、不激活系统 VPN）：
 * App 内联网与 AI 请求会读取本地保存的代理配置并走该代理。本类作为系统级
 * VPN 接管的接入骨架/占位服务，供后续 go-mobile 原生库演进时填充真实隧道逻辑。
 */
class ProxyVpnService : VpnService() {

    companion object {
        const val ACTION_CONNECT = "com.example.smartenglish.VPN_CONNECT"
        const val ACTION_DISCONNECT = "com.example.smartenglish.VPN_DISCONNECT"
    }

    private var tunInterface: ParcelFileDescriptor? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_DISCONNECT -> {
                stopSelf()
                return START_NOT_STICKY
            }
            else -> startTun()
        }
        return START_STICKY
    }

    private fun startTun() {
        // 骨架占位：创建 TUN 接口。真实接管需在此获得 fd 并交给同进程核心。
        val builder = Builder()
        builder.setSession("AFloat")
        builder.addAddress("10.0.0.1", 24)
        builder.addRoute("0.0.0.0", 0)
        tunInterface = builder.establish()
    }

    override fun onDestroy() {
        tunInterface?.close()
        super.onDestroy()
    }
}