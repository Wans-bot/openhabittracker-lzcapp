/**
 * OpenHabitTracker 默认中文注入（browser 阶段）
 *
 * 为什么需要：上游新用户的界面语言默认值是 en（SettingsModel.Culture 的代码默认值），
 * 中文语言包本身完整，但全新安装第一眼是英文，首装自动生成的欢迎笔记也会是英文。
 * 这里用上游自己的公开接口把当前部署账号的设置改成 zh。
 *
 * 与 content/init.sh 的关系：init.sh 做的是同一件事，但要求 lzc-manifest.yml 里有一个跑它的
 * 服务；本脚本是浏览器侧的兜底（登录页不跑，见 manifest 的 unless: /login），两者都幂等。
 *
 * 契约（见 lzc-manifest.yml 的 oht-set-chinese）：
 *   params.user / params.password 由部署参数渲染传入，不写死在脚本里。
 */
(() => {
  const params = (typeof ctx !== "undefined" && ctx && ctx.params) || {};
  const user = params.user || params.username;
  const password = params.password;

  if (!user || !password) return;
  if (window.__ohtSetChineseRunning) return;
  window.__ohtSetChineseRunning = true;

  const endpoint = "/api/DataAccess/settings";

  const cultureOf = (s) => String((s && (s.Culture || s.culture)) || "");

  const run = async () => {
    // 1) 用部署账号换 JWT（和 init.sh 第 1 步同一个接口）
    const tr = await fetch("/api/Auth/jwt-token", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ userName: user, password }),
    });
    if (!tr.ok) return;
    const tj = await tr.json().catch(() => null);
    const jwt = tj && (tj.JwtToken || tj.jwtToken || tj.token);
    if (!jwt) return;

    // 2) 读当前设置，已经是 zh 就什么都不做
    const gr = await fetch(endpoint, { headers: { Authorization: "Bearer " + jwt } });
    if (!gr.ok) return;
    const settings = await gr.json().catch(() => null);
    if (!settings || typeof settings !== "object") return;
    if (cultureOf(settings).toLowerCase() === "zh") {
      window.__ohtSetChineseRunning = false;
      return;
    }

    // 3) 只改语言，其它字段原样写回（与 init.sh 的做法一致）
    const patched = { ...settings };
    if ("culture" in settings && !("Culture" in settings)) patched.culture = "zh";
    else patched.Culture = "zh";

    const pr = await fetch(endpoint, {
      method: "PUT",
      headers: { "Content-Type": "application/json", Authorization: "Bearer " + jwt },
      body: JSON.stringify(patched),
    });
    window.__ohtSetChineseRunning = false;
    if (pr.ok) location.reload();
  };

  run().catch(() => {
    window.__ohtSetChineseRunning = false;
  });
})();
