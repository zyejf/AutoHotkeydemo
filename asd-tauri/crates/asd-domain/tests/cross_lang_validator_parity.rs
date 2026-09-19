//! 跨语言校验对拍装置（TD-067）的 **Rust 半边**。
//!
//! 背景：`asd-domain/src/validator.rs` 与 `infrastructure/config_validator.ahk` 是同一套
//! 业务规则的**两套独立实现**（10 种模式、热键格式、时间序列上下界、控制热键、
//! `HoldSettings`）。在补本装置之前，两侧没有任何比对机制 —— 任一侧改了规则，
//! 另一侧不会有任何信号，分歧只在「用户存不下配置」或「AHK 侧静默拒绝」时才暴露。
//!
//! 本文件把同一批配置样本（夹具：`tests/fixtures/configs/cross_lang_validator_cases.json`）
//! 喂给 Rust 侧的 `ConfigValidator::validate_config`，逐例与夹具里登记的 AHK 侧结论比对。
//!
//! ⚠️ **AHK 那一列不是猜的**：它由 `tools/ahk-probes/p_cross_lang_validator.ahk` 实际
//! 执行 AHK 校验器产出。任何人改了 AHK 侧校验规则，都应重跑那个脚本并把结果写回夹具的
//! `ahk_has_error`；否则本装置会退化成「只钉住 Rust 侧的单向断言」。
//!
//! 三条用例的分工：
//! 1. `parity_core_cases_agree` —— 契约核心：两侧结论**必须一致**，任一侧改坏即红；
//! 2. `known_divergence_cases_are_frozen` —— 已知分歧（明细登记在台账 TD-067）：钉住
//!    Rust 侧当前结论，任何一侧**有意收敛**也会让本例变红，逼人显式复核后再挪进核心集；
//! 3. `fixture_self_check` —— 装置自检：防止夹具读空／解析失效时「空集对空集」假装通过，
//!    并用夹具里的 `min_cases` 棘轮基线挡住「静默删用例」（只增不减，缩小须显式下调并说明理由）。
//!
//! 只比**是否判定为非法（`has_error`）**，不比错误文案：两侧文案本就不同（语言与措辞），
//! 比文案会制造大量无意义的噪音，而「一侧判合法、另一侧判非法」才是真正的契约分裂。

use asd_domain::config::Config;
use asd_domain::validator::ConfigValidator;
use serde_json::Value;
use std::path::Path;

/// 对拍夹具：放在仓库根 `tests/fixtures/configs/` 下，与 AHK 侧探针共用同一份。
const CASES_PATH: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../../tests/fixtures/configs/cross_lang_validator_cases.json"
);

/// 夹具里的一个对拍用例。
struct Case {
    id: String,
    config: Value,
    /// 夹具登记的 Rust 侧结论：是否存在 ERROR 级问题。
    rust_has_error: bool,
    /// 夹具登记的 AHK 侧结论（由 `p_cross_lang_validator.ahk` 实跑产出）。
    ahk_has_error: bool,
}

impl Case {
    /// 两侧结论一致 = 契约核心用例；不一致 = 已知分歧用例。
    fn is_parity(&self) -> bool {
        self.rust_has_error == self.ahk_has_error
    }
}

fn read_fixture_doc() -> Value {
    let raw = std::fs::read_to_string(CASES_PATH)
        .unwrap_or_else(|e| panic!("读取对拍夹具失败 `{CASES_PATH}`: {e}"));
    serde_json::from_str(&raw).unwrap_or_else(|e| panic!("对拍夹具不是合法 JSON: {e}"))
}

/// 夹具登记的**棘轮基线**（历史最高用例条数）。
///
/// 为什么放在**夹具数据**里而不是写死在测试代码里：写死的下限（原先是 `16`）加了用例不会跟着涨，
/// 于是「每次删一点」完全静默 —— 另外两条用例只会「少比一条」，不会报错。这与 TD-058 里 G3f
/// 覆盖率棘轮踩过的坑同构：差集检查挡不住「每次缩一点」的温水煮蛙，真正缺的是**水位下限**。
///
/// 放在夹具里还有第二个好处：新增用例时上调基线，是与加样本同一次改动、同一个 diff 里的动作，
/// 本来就该留下痕迹；而改测试代码则容易被当成「顺手改期望值」的假守护路径。
fn load_min_cases() -> usize {
    let doc = read_fixture_doc();
    doc.get("min_cases")
        .and_then(Value::as_u64)
        .and_then(|n| usize::try_from(n).ok())
        .unwrap_or_else(|| {
            panic!(
                "对拍夹具缺少 `min_cases`（棘轮基线 = 历史最高用例条数）。\n\
                 → 该字段是「删用例会被发现」的**唯一**保障，字段缺失即等于守护失效；\n\
                 → 请补回 `\"min_cases\": <cases 数组当前条数>`（当前应为 17）。"
            )
        })
}

fn load_cases() -> Vec<Case> {
    let doc = read_fixture_doc();
    let arr = doc
        .get("cases")
        .and_then(Value::as_array)
        .unwrap_or_else(|| panic!("对拍夹具缺少 `cases` 数组: `{CASES_PATH}`"));

    arr.iter()
        .map(|c| {
            let id = c
                .get("id")
                .and_then(Value::as_str)
                .unwrap_or("<no-id>")
                .to_string();
            let config = c
                .get("config")
                .cloned()
                .unwrap_or_else(|| panic!("用例 `{id}` 缺少 `config`"));
            let expect = c
                .get("expect")
                .cloned()
                .unwrap_or_else(|| panic!("用例 `{id}` 缺少 `expect`"));
            let flag = |side: &str, id: &str| {
                expect
                    .get(side)
                    .and_then(Value::as_bool)
                    .unwrap_or_else(|| panic!("用例 `{id}` 的 `expect.{side}` 缺失或不是 bool"))
            };
            let rust_has_error = flag("rust_has_error", &id);
            let ahk_has_error = flag("ahk_has_error", &id);
            Case {
                id,
                config,
                rust_has_error,
                ahk_has_error,
            }
        })
        .collect()
}

/// 跑 Rust 侧校验器，返回 `(是否拒收, 拒收原因)`。
///
/// ⚠️ **拒收有两道门，两道都算「Rust 侧判非法」**：
/// 1. `Config` **反序列化阶段** —— 例如 `mode` 不在已知 10 种模式里，
///    `GroupConfig::deserialize` 直接返回 `unknown mode` 错误，根本走不到校验器；
///    这比产出一条 ERROR 更硬（AHK 侧同场景是校验器产出 ERROR 级消息）。
/// 2. `ConfigValidator::validate_config` **产出 ERROR**。
///
/// 只取第 2 道会把「未知模式」这类样本误判成「Rust 侧合法」，正是本装置要防的假绿。
fn rust_rejects(config: &Value) -> (bool, String) {
    match serde_json::from_value::<Config>(config.clone()) {
        Err(e) => (true, format!("反序列化拒收: {e}")),
        Ok(cfg) => {
            let result = ConfigValidator::validate_config(&cfg);
            let n = result.errors.len();
            (n > 0, format!("校验 ERROR {n} 条"))
        }
    }
}

fn rust_has_error(config: &Value) -> bool {
    rust_rejects(config).0
}

#[test]
fn parity_core_cases_agree() {
    let cases = load_cases();
    let core: Vec<&Case> = cases.iter().filter(|c| c.is_parity()).collect();
    assert!(
        !core.is_empty(),
        "夹具里没有任何「两侧结论一致」的核心用例 —— 夹具可能被清空或解析失效"
    );

    let mut broken = Vec::new();
    for c in &core {
        let actual = rust_has_error(&c.config);
        if actual != c.rust_has_error {
            broken.push(format!(
                "  · {}: 夹具声明两侧一致 (has_error={})，Rust 实测 has_error={}",
                c.id, c.rust_has_error, actual
            ));
        }
    }
    assert!(
        broken.is_empty(),
        "契约核心用例出现跨语言结论分裂（共 {} 条核心用例）：\n{}\n\
         → 若是有意修改 Rust 侧规则，请同步 `infrastructure/config_validator.ahk` 并重跑 \
         `tools/ahk-probes/p_cross_lang_validator.ahk` 更新夹具的 `ahk_has_error`。",
        core.len(),
        broken.join("\n")
    );
}

#[test]
fn known_divergence_cases_are_frozen() {
    let cases = load_cases();
    let diverging: Vec<&Case> = cases.iter().filter(|c| !c.is_parity()).collect();
    assert!(
        !diverging.is_empty(),
        "夹具里没有任何已知分歧用例 —— 若分歧已全部消除，请把用例并入核心集并更新台账 TD-067"
    );

    for c in &diverging {
        let actual = rust_has_error(&c.config);
        assert_eq!(
            actual, c.rust_has_error,
            "已知分歧用例 `{}` 的 Rust 侧结论发生漂移（夹具登记 {}，AHK 侧 {}，Rust 实测 {}）。\n\
             → 若是**有意**让两侧收敛：把该用例移出分歧集、确认 AHK 侧同步改了、更新台账 TD-067；\n\
             → 若是无意漂移：这是校验行为回归，请修回来。",
            c.id, c.rust_has_error, c.ahk_has_error, actual
        );
    }
}

#[test]
fn fixture_self_check() {
    // 锚点：夹具路径真实存在。没有这条，路径写错时 `load_cases` 的 panic 只会在
    // 另外两条用例里各报一次，容易被误读成「用例逻辑错」而不是「夹具丢了」。
    assert!(
        Path::new(CASES_PATH).is_file(),
        "对拍夹具不存在: `{CASES_PATH}`"
    );

    let cases = load_cases();
    let baseline = load_min_cases();

    // 棘轮：只增不减。两个方向都拦，但语义与处置不同 —— 缩小是「可能丢覆盖」，增大是「基线没跟上」。
    assert!(
        cases.len() >= baseline,
        "对拍夹具用例数从 {} 条缩到 {} 条 —— 删除用例会静默丢失覆盖：\
         `parity_core_cases_agree` 只会「少比一条」，`known_divergence_cases_are_frozen` 只会「少冻结一条」，\
         两条都不报错。\n\
         → 若确需删除：同步把夹具的 `min_cases` 下调到 {}，并在 commit message 写明删除理由\
         （本装置的显式出口，对应 G3f 的 `--allow-scope-shrink`）；\n\
         → 若为误删：请把用例加回来。",
        baseline,
        cases.len(),
        cases.len()
    );
    assert!(
        cases.len() <= baseline,
        "对拍夹具已增至 {} 条，但棘轮基线 `min_cases` 仍是 {} —— 不推进基线的话，\
         后续删回 {} 条将无人发现。\n\
         → 请把夹具的 `min_cases` 上调到 {}。",
        cases.len(),
        baseline,
        baseline,
        cases.len()
    );
    assert!(
        cases.iter().any(|c| c.is_parity() && c.rust_has_error),
        "缺少「两侧都判非法」的核心用例 —— 非法样本覆盖面不足"
    );
    assert!(
        cases.iter().any(|c| c.is_parity() && !c.rust_has_error),
        "缺少「两侧都判合法」的核心用例 —— 合法样本覆盖面不足"
    );
    assert!(
        cases.iter().any(|c| !c.is_parity() && c.ahk_has_error),
        "缺少「AHK 判非法、Rust 判合法」的分歧样本"
    );
    assert!(
        cases.iter().any(|c| !c.is_parity() && c.rust_has_error),
        "缺少「Rust 判非法、AHK 判合法」的分歧样本"
    );

    // 每个样本都必须能被 Rust 侧真正校验一遍（反序列化失败会 panic，不会静默跳过）。
    for c in &cases {
        let _ = rust_has_error(&c.config);
    }
}
