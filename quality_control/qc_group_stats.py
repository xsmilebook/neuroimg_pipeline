import argparse
import os
import sys
import pandas as pd


def normalize_yes(val):
    if pd.isna(val):
        return False
    s = str(val).strip().lower()
    return s == "yes"


def normalize_int(val):
    if pd.isna(val):
        return None
    try:
        # Some counts may be stored as float strings like '180.0'
        return int(float(val))
    except Exception:
        return None


def normalize_float(val):
    if pd.isna(val):
        return None
    try:
        return float(val)
    except Exception:
        return None


def assign_group_flags(disorder_str):
    # disorder_str can be NaN/empty → treated as TD
    if pd.isna(disorder_str):
        s = ""
    else:
        s = str(disorder_str).strip()

    is_adhd = "ADHD" in s
    is_md = "MD" in s
    is_dd = "DD" in s
    # TD group: explicitly TD or empty
    is_td = (s == "TD") or (s == "")
    is_non_adhd = not is_adhd

    return {
        "ADHD": is_adhd,
        "非ADHD": is_non_adhd,
        "MD": is_md,
        "DD": is_dd,
        "TD": is_td,
    }


def compute_modality_pass_flags(row, expected_lengths, fd_threshold=0.2):
    # anat：T1/T2 都为 yes 视为通过；无失败，总计只计 yes
    anat_t1_yes = normalize_yes(row.get("anat_T1"))
    anat_t2_yes = normalize_yes(row.get("anat_T2"))
    anat_pass = anat_t1_yes and anat_t2_yes

    # fmap：direction 为 yes 视为通过；无失败，总计只计 yes
    fmap_dir_yes = normalize_yes(row.get("fmap_direction"))
    fmap_pass = fmap_dir_yes

    # 任务/静息：FD 有值才进入统计；通过需长度匹配且 FD<=阈值
    def pass_with_fd(fd_val, len_val, expected_len):
        if fd_val is None:
            return False
        len_ok = (len_val == expected_len)
        fd_ok = (fd_val <= fd_threshold)
        return len_ok and fd_ok

    rest1_len = normalize_int(row.get("rest1"))
    rest1_fd = normalize_float(row.get("rest1_fd"))
    rest1_pass = pass_with_fd(rest1_fd, rest1_len, expected_lengths["rest1"])

    rest2_len = normalize_int(row.get("rest2"))
    rest2_fd = normalize_float(row.get("rest2_fd"))
    rest2_pass = pass_with_fd(rest2_fd, rest2_len, expected_lengths["rest2"])

    sst_len = normalize_int(row.get("sst"))
    sst_fd = normalize_float(row.get("sst_fd"))
    sst_pass = pass_with_fd(sst_fd, sst_len, expected_lengths["sst"])

    nback_len = normalize_int(row.get("nback"))
    nback_fd = normalize_float(row.get("nback_fd"))
    nback_pass = pass_with_fd(nback_fd, nback_len, expected_lengths["nback"])

    switch_len = normalize_int(row.get("switch"))
    switch_fd = normalize_float(row.get("switch_fd"))
    switch_pass = pass_with_fd(switch_fd, switch_len, expected_lengths["switch"])

    return {
        "anat_pass": anat_pass,
        "fmap_pass": fmap_pass,
        "rest1_pass": rest1_pass,
        "rest2_pass": rest2_pass,
        "sst_pass": sst_pass,
        "nback_pass": nback_pass,
        "switch_pass": switch_pass,
        # 供“是否纳入统计”使用（仅任务/静息有该判定）
        "rest1_fd_present": rest1_fd is not None,
        "rest2_fd_present": rest2_fd is not None,
        "sst_fd_present": sst_fd is not None,
        "nback_fd_present": nback_fd is not None,
        "switch_fd_present": switch_fd is not None,
    }


def summarize_modality(df, group_name, group_mask, modality, expected_lengths, fd_threshold=0.2):
    # anat/fmap：总计只包括 yes，失败为 0
    if modality == "anat":
        passes = int((df.loc[group_mask, "anat_pass"]).sum())
        total = passes
        fails = 0
    elif modality == "fmap":
        passes = int((df.loc[group_mask, "fmap_pass"]).sum())
        total = passes
        fails = 0
    else:
        # rest1/rest2/sst/nback/switch：总计包含 FD 有值的个体，失败为（总计-通过）
        fd_present_col = f"{modality}_fd_present"
        pass_col = f"{modality}_pass"
        considered = df.loc[group_mask & (df[fd_present_col] == True)]
        total = int(considered.shape[0])
        passes = int(considered[pass_col].sum())
        fails = total - passes

    return {
        "group": group_name,
        "modality": modality,
        "pass": passes,
        "fail": fails,
        "total": total,
    }


def main():
    parser = argparse.ArgumentParser(description="按组统计各模态 QC 通过/失败/合计数量（anat/fmap 仅统计 yes；rest/task 以FD存在且阈值为准）")
    parser.add_argument(
        "--input",
        default=r"e:\\projects\\neuroimg_pipeline\\datasets\\EFNY\\EFI\\QC_folder\\EFI_QC_merged.csv",
        help="输入合并后的 CSV 路径",
    )
    parser.add_argument(
        "--output",
        default=r"e:\\projects\\neuroimg_pipeline\\datasets\\EFNY\\EFI\\QC_folder\\EFI_QC_group_stats.csv",
        help="输出统计 CSV 路径（包含 group+modality 的行）",
    )
    parser.add_argument(
        "--fd_threshold",
        type=float,
        default=0.2,
        help="任务/静息的 FD 阈值",
    )
    parser.add_argument("--expected_rest1", type=int, default=180, help="rest1 期望长度")
    parser.add_argument("--expected_rest2", type=int, default=180, help="rest2 期望长度")
    parser.add_argument("--expected_sst", type=int, default=161, help="sst 期望长度")
    parser.add_argument("--expected_nback", type=int, default=219, help="nback 期望长度")
    parser.add_argument("--expected_switch", type=int, default=209, help="switch 期望长度")
    # 不再需要头动阈值/长度参数，统计仅基于存在性

    args = parser.parse_args()

    if not os.path.exists(args.input):
        print(f"输入文件不存在: {args.input}")
        sys.exit(1)

    df = pd.read_csv(args.input)

    expected_lengths = {
        "rest1": args.expected_rest1,
        "rest2": args.expected_rest2,
        "sst": args.expected_sst,
        "nback": args.expected_nback,
        "switch": args.expected_switch,
    }

    # Compute pass flags for each row（按阈值和期望长度）
    pass_rows = df.apply(lambda r: compute_modality_pass_flags(r, expected_lengths, args.fd_threshold), axis=1, result_type="expand")
    for col in pass_rows.columns:
        df[col] = pass_rows[col]

    # Group flags
    group_flags = df["障碍类型"].apply(assign_group_flags)
    group_df = pd.DataFrame(group_flags.tolist())
    for col in group_df.columns:
        df[f"group_{col}"] = group_df[col]

    # Summaries per modality for each group and ALL
    summaries = []
    groups = ["ADHD", "非ADHD", "MD", "DD", "TD"]
    modalities = ["anat", "fmap", "rest1", "rest2", "sst", "nback", "switch"]

    for group in groups:
        group_mask = df[f"group_{group}"] == True
        for modality in modalities:
            summaries.append(
                summarize_modality(df, group, group_mask, modality, expected_lengths, args.fd_threshold)
            )

    # ALL subjects
    all_mask = pd.Series([True] * df.shape[0], index=df.index)
    for modality in modalities:
        summaries.append(
            summarize_modality(df, "ALL", all_mask, modality, expected_lengths, args.fd_threshold)
        )

    out_df = pd.DataFrame(summaries, columns=["group", "modality", "pass", "fail", "total"])
    # Save summary
    out_dir = os.path.dirname(args.output)
    if out_dir and not os.path.exists(out_dir):
        os.makedirs(out_dir, exist_ok=True)
    out_df.to_csv(args.output, index=False)

    # Also print a readable summary
    print("QC分组统计（anat/fmap 仅统计 yes；rest/task 以FD存在并满足时长+阈值为通过）：")
    for modality in modalities:
        print(f"\n[{modality}]")
        for group in groups + ["ALL"]:
            row = out_df[(out_df.group == group) & (out_df.modality == modality)].iloc[0]
            print(f"{group}: 通过 {row['pass']} | 失败 {row['fail']} | 合计 {row['total']}")


if __name__ == "__main__":
    main()