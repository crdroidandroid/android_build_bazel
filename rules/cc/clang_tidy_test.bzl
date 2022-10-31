"""
Copyright (C) 2022 The Android Open Source Project

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""

load("@bazel_skylib//lib:new_sets.bzl", "sets")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load(":clang_tidy.bzl", "generate_clang_tidy_actions")

_PACKAGE_HEADER_FILTER = "^build/bazel/rules/cc/"
_DEFAULT_CHECKS = [
    "android-*",
    "bugprone-*",
    "cert-*",
    "clang-diagnostic-unused-command-line-argument",
    "google-build-explicit-make-pair",
    "google-build-namespaces",
    "google-runtime-operator",
    "google-upgrade-*",
    "misc-*",
    "performance-*",
    "portability-*",
    "-bugprone-assignment-in-if-condition",
    "-bugprone-easily-swappable-parameters",
    "-bugprone-narrowing-conversions",
    "-misc-const-correctness",
    "-misc-no-recursion",
    "-misc-non-private-member-variables-in-classes",
    "-misc-unused-parameters",
    "-performance-no-int-to-ptr",
    "-clang-analyzer-security.insecureAPI.DeprecatedOrUnsafeBufferHandling",
    "-readability-function-cognitive-complexity",
    "-bugprone-reserved-identifier*",
    "-cert-dcl51-cpp",
    "-cert-dcl37-c",
    "-readability-qualified-auto",
    "-bugprone-implicit-widening-of-multiplication-result",
    "-cert-err33-c",
    "-bugprone-unchecked-optional-access",
]
_DEFAULT_CHECKS_AS_ERRORS = [
    "-bugprone-assignment-in-if-condition",
    "-bugprone-branch-clone",
    "-bugprone-signed-char-misuse",
    "-misc-const-correctness",
]
_EXTRA_ARGS_BEFORE = [
    "-D__clang_analyzer__",
    "-Xclang",
    "-analyzer-config",
    "-Xclang",
    "c++-temp-dtor-inlining=false",
]

def _clang_tidy_impl(ctx):
    tidy_outs = generate_clang_tidy_actions(
        ctx,
        ctx.attr.copts,
        ctx.attr.deps,
        ctx.files.srcs,
        ctx.files.hdrs,
        ctx.attr.language,
        ctx.attr.tidy_flags,
        ctx.attr.tidy_checks,
        ctx.attr.tidy_checks_as_errors,
        ctx.attr.tidy_timeout_srcs,
    )
    return [
        DefaultInfo(files = depset(tidy_outs)),
    ]

_clang_tidy = rule(
    implementation = _clang_tidy_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "deps": attr.label_list(),
        "copts": attr.string_list(),
        "hdrs": attr.label_list(allow_files = True),
        "language": attr.string(values = ["c++", "c"], default = "c++"),
        "tidy_checks": attr.string_list(),
        "tidy_checks_as_errors": attr.string_list(),
        "tidy_flags": attr.string_list(),
        "tidy_timeout_srcs": attr.label_list(allow_files = True),
        "_clang_tidy_sh": attr.label(
            default = Label("@//prebuilts/clang/host/linux-x86:clang-tidy.sh"),
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            doc = "The clang tidy shell wrapper",
        ),
        "_clang_tidy": attr.label(
            default = Label("@//prebuilts/clang/host/linux-x86:clang-tidy"),
            allow_single_file = True,
            executable = True,
            cfg = "exec",
            doc = "The clang tidy executable",
        ),
        "_clang_tidy_real": attr.label(
            default = Label("@//prebuilts/clang/host/linux-x86:clang-tidy.real"),
            allow_single_file = True,
            executable = True,
            cfg = "exec",
        ),
        "_with_tidy": attr.label(
            default = "//build/bazel/flags/cc/tidy:with_tidy",
        ),
        "_allow_local_tidy_true": attr.label(
            default = "//build/bazel/flags/cc/tidy:allow_local_tidy_true",
        ),
        "_with_tidy_flags": attr.label(
            default = "//build/bazel/flags/cc/tidy:with_tidy_flags",
        ),
        "_default_tidy_header_dirs": attr.label(
            default = "//build/bazel/flags/cc/tidy:default_tidy_header_dirs",
        ),
        "_tidy_timeout": attr.label(
            default = "//build/bazel/flags/cc/tidy:tidy_timeout",
        ),
    },
    toolchains = ["@bazel_tools//tools/cpp:toolchain_type"],
    fragments = ["cpp"],
)

def _get_all_arg(env, actions, argname):
    args = []
    for a in actions[0].argv:
        if a.startswith(argname):
            args.append(a[len(argname):])
    asserts.false(env, args == [], "could not arguments that start with `{}`".format(argname))
    return args

def _get_single_arg(env, actions, argname):
    arg = _get_all_arg(env, actions, argname)
    asserts.true(env, len(arg) == 1, "too many `%s` arguments. expected 1; got %s" % (argname, len(arg)))
    return arg[0]

def _checks_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)

    checks = _get_single_arg(env, actions, "-checks=").split(",")
    asserts.set_equals(env, sets.make(ctx.attr.expected_checks), sets.make(checks))

    checks_as_errors = _get_single_arg(env, actions, "-warnings-as-errors=").split(",")
    asserts.set_equals(env, sets.make(ctx.attr.expected_checks_as_errors), sets.make(checks_as_errors))

    return analysistest.end(env)

_checks_test = analysistest.make(
    _checks_test_impl,
    attrs = {
        "expected_checks": attr.string_list(mandatory = True),
        "expected_checks_as_errors": attr.string_list(mandatory = True),
    },
)

def _copts_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)

    args = actions[0].argv
    clang_flags = []
    for i, a in enumerate(args):
        if a == "--" and len(args) > i + 1:
            clang_flags = args[i + 1:]
            break
    asserts.true(
        env,
        len(clang_flags) > 0,
        "no flags passed to clang; all arguments: %s" % args,
    )

    for expected_arg in ctx.attr.expected_copts:
        asserts.true(
            env,
            expected_arg in clang_flags,
            "expected `%s` not present in clang flags" % expected_arg,
        )

    return analysistest.end(env)

_copts_test = analysistest.make(
    _copts_test_impl,
    attrs = {
        "expected_copts": attr.string_list(mandatory = True),
    },
)

def _tidy_flags_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)

    args = actions[0].argv
    tidy_flags = []
    for i, a in enumerate(args):
        if a == "--" and len(args) > i + 1:
            tidy_flags = args[:i]
    asserts.true(
        env,
        len(tidy_flags) > 0,
        "no tidy flags passed to clang-tidy; all arguments: %s" % args,
    )

    for expected_arg in ctx.attr.expected_tidy_flags:
        asserts.true(
            env,
            expected_arg in tidy_flags,
            "expected `%s` not present in flags to clang-tidy" % expected_arg,
        )

    header_filter = _get_single_arg(env, actions, "-header-filter=")
    asserts.true(
        env,
        header_filter == ctx.attr.expected_header_filter,
        (
            "expected header-filter to have value `%s`; got `%s`" %
            (ctx.attr.expected_header_filter, header_filter)
        ),
    )

    extra_arg_before = _get_all_arg(env, actions, "-extra-arg-before=")
    for expected_arg in ctx.attr.expected_extra_arg_before:
        asserts.true(
            env,
            expected_arg in extra_arg_before,
            "did not find expected flag `%s` in args to clang-tidy" % expected_arg,
        )

    return analysistest.end(env)

_tidy_flags_test = analysistest.make(
    _tidy_flags_test_impl,
    attrs = {
        "expected_tidy_flags": attr.string_list(mandatory = True),
        "expected_header_filter": attr.string(mandatory = True),
        "expected_extra_arg_before": attr.string_list(mandatory = True),
    },
)

def _test_clang_tidy():
    name = "checks"
    test_name = name + "_test"
    checks_test_name = test_name + "_checks"
    copts_test_name = test_name + "_copts"
    tidy_flags_test_name = test_name + "_tidy_flags"

    _clang_tidy(
        name = name,
        srcs = ["a.cpp"],
        copts = ["-asdf1", "-asdf2"],
        tidy_flags = ["-tidy-flag1", "-tidy-flag2"],
        tags = ["manual"],
    )

    _checks_test(
        name = checks_test_name,
        target_under_test = name,
        expected_checks = _DEFAULT_CHECKS,
        expected_checks_as_errors = _DEFAULT_CHECKS_AS_ERRORS,
    )

    _copts_test(
        name = copts_test_name,
        target_under_test = name,
        expected_copts = ["-asdf1", "-asdf2"],
    )

    _tidy_flags_test(
        name = tidy_flags_test_name,
        target_under_test = name,
        expected_tidy_flags = ["-tidy-flag1", "-tidy-flag2"],
        expected_header_filter = _PACKAGE_HEADER_FILTER,
        expected_extra_arg_before = _EXTRA_ARGS_BEFORE,
    )

    return [
        checks_test_name,
        copts_test_name,
        tidy_flags_test_name,
    ]

def clang_tidy_test_suite(name):
    native.test_suite(
        name = name,
        tests = _test_clang_tidy(),
    )
