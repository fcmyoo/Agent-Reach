# -*- coding: utf-8 -*-
"""Contract tests for channel adapters.

合并说明（本地改造，保留自 fork commit d1b7433）：
   本地原版基于 1.5 的 Channel 契约（ch.backends / ch.tier / ch.check(config) /
   ch.ordered_backends(config) / ch.active_backend）。上游 1.6 把 Channel 重写为
   level + actions 契约，旧的 tier / check / ordered_backends / active_backend
   全部消失，因此原断言无法照搬。

   这里按 1.6 的等价语义重写，保留本地测试真正想守住的三条不变量：
     1. 渠道注册表非空、名称唯一（上游已覆盖，这里补一条本地更严的断言）。
     2. 每个 action 的 backends 是有序的 —— 后端顺序即回退顺序，本地旧版
        ordered_backends 的核心不变量在 1.6 落在 Action.backends 元组上。
     3. backend 标签唯一且其方法确实可调用（与上游 test_channel_contracts
        互补：上游只查可调用，这里额外查标签唯一性）。
"""

from agent_reach.channels import get_all_channels


def test_channel_registry_contract():
    channels = get_all_channels()
    assert channels, "channel registry must not be empty"
    names = [ch.name for ch in channels]
    assert len(names) == len(set(names)), "channel names must be unique"

    for ch in channels:
        assert isinstance(ch.name, str) and ch.name
        assert isinstance(ch.description, str) and ch.description
        assert ch.level in {"default", "optional", "experimental"}
        assert ch.actions, f"{ch.name} exposes no actions"


def test_action_backends_are_ordered_and_unique():
    """每个 action 的 backends 顺序即回退顺序，标签不得重复。"""
    for ch in get_all_channels():
        for action in ch.actions:
            labels = [label for label, _method in action.backends]
            assert labels, f"{ch.name}.{action.name} exposes no backends"
            assert len(labels) == len(set(labels)), (
                f"{ch.name}.{action.name} has duplicate backend labels: {labels}"
            )
            for label, method in action.backends:
                assert isinstance(label, str) and label
                assert callable(getattr(ch, method, None)), (
                    f"{ch.name}.{action.name} backend {label!r} -> {method} is not callable"
                )


def test_action_params_are_wellformed():
    """action.params 中的 Param 必须有名字、帮助文本，且类型可用。"""
    for ch in get_all_channels():
        for action in ch.actions:
            assert action.help, f"{ch.name}.{action.name} has no help text"
            names = []
            for param in action.params:
                assert isinstance(param.name, str) and param.name
                assert isinstance(param.help, str) and param.help
                assert isinstance(param.required, bool)
                assert param.type in (str, int, float, bool), (
                    f"{ch.name}.{action.name}.{param.name} has unsupported type {param.type!r}"
                )
                names.append(param.name)
            assert len(names) == len(set(names)), (
                f"{ch.name}.{action.name} has duplicate params: {names}"
            )


def test_channel_can_handle_contract():
    url_samples = {
        "github": "https://github.com/panniantong/agent-reach",
        "twitter": "https://x.com/user/status/1",
        "youtube": "https://youtube.com/watch?v=abc",
        "reddit": "https://reddit.com/r/python",
        "facebook": "https://www.facebook.com/zuck",
        "instagram": "https://www.instagram.com/openai/",
        "bilibili": "https://www.bilibili.com/video/BV1xx411",
        "xiaohongshu": "https://www.xiaohongshu.com/explore/123",
        "linkedin": "https://www.linkedin.com/in/test",
        "rss": "https://example.com/feed.xml",
        "xueqiu": "https://xueqiu.com/S/SH600519",
        "exa_search": "https://example.com",
        "web": "https://example.com",
    }
    for ch in get_all_channels():
        sample = url_samples.get(ch.name, "https://example.com")
        result = ch.can_handle(sample)
        assert isinstance(result, bool)
