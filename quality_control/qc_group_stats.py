import argparse
import os
import sys
import pandas as pd

def _parse_sheet_arg(sheet_arg):
    """解析 --sheet 参数，支持工作表名称或索引。
    返回值可为 int（索引，从 0 开始）或 str（名称）；None 或空字符串时默认第一个工作表。
    """
    if sheet_arg is None:
        return 0
    if isinstance(sheet_arg, int):
        return sheet_arg
    try:
        s = str(sheet_arg).strip()
        if s == "":
            return 0
        if s.isdigit():
            return int(s)
        return s
    except Exception:
        return 0

def read_table(input_path, sheet_arg=None):
    ext = os.path.splitext(input_path)[1].lower()
    if ext in [".xlsx", ".xls"]:
        sheet = _parse_sheet_arg(sheet_arg)
        try:
            df = pd.read_excel(input_path, sheet_name=sheet)
        except Exception as e:
            print(f"读取 Excel 失败: {e}")
            sys.exit(1)
        return df, ext
    else:
        try:
            df = pd.read_csv(input_path)
        except Exception as e:
            print(f"读取 CSV 失败: {e}")
            sys.exit(1)
        return df, ext

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

    is_adhd = ("ADHD" in s) and ("DD" not in s) and ("MD" not in s)
    is_md = "MD" in s
    # DD 仅在出现 DD 且不出现 MD 时归为 DD 组
    is_dd = ("DD" in s) and ("MD" not in s)
    # TD group: explicitly TD or empty
    is_td = ("TD" in s) or (s == "")
    is_non_adhd = not is_adhd

    return {
        "ADHD": is_adhd,
        "非ADHD": is_non_adhd,
        "MD": is_md,
        "DD": is_dd,
        "TD": is_td,
    }


def compute_modality_pass_flags(row, expected_lengths, fd_threshold=0.2, dwi_fd_threshold=1.43):
    # anat：T1/T2 都为 yes 视为通过；无失败，总计只计 yes
    anat_t1_yes = normalize_yes(row.get("anat_T1"))
    anat_t2_yes = normalize_yes(row.get("anat_T2"))
    anat_pass = anat_t1_yes and anat_t2_yes

    # fmap：direction 为 yes 视为通过；无失败，总计只计 yes
    fmap_dir_yes = normalize_yes(row.get("fmap_direction"))
    fmap_pass = fmap_dir_yes

    # 任务/静息：总计仅以 FD 是否存在为准；通过需长度匹配且 FD<=阈值
    def pass_with_len_fd(fd_val, len_val, expected_len):
        # 通过需：长度匹配且 FD 有值且不超过阈值
        if len_val is None:
            return False
        if fd_val is None:
            return False
        len_ok = (len_val == expected_len)
        fd_ok = (fd_val <= fd_threshold)
        return len_ok and fd_ok

    rest1_len = normalize_int(row.get("rest1"))
    rest1_fd = normalize_float(row.get("rest1_fd"))
    rest1_pass = pass_with_len_fd(rest1_fd, rest1_len, expected_lengths["rest1"])
    rest1_fd_present = rest1_fd is not None

    rest2_len = normalize_int(row.get("rest2"))
    rest2_fd = normalize_float(row.get("rest2_fd"))
    rest2_pass = pass_with_len_fd(rest2_fd, rest2_len, expected_lengths["rest2"])
    rest2_fd_present = rest2_fd is not None

    sst_len = normalize_int(row.get("sst"))
    sst_fd = normalize_float(row.get("sst_fd"))
    sst_pass = pass_with_len_fd(sst_fd, sst_len, expected_lengths["sst"])
    sst_fd_present = sst_fd is not None

    nback_len = normalize_int(row.get("nback"))
    nback_fd = normalize_float(row.get("nback_fd"))
    nback_pass = pass_with_len_fd(nback_fd, nback_len, expected_lengths["nback"])
    nback_fd_present = nback_fd is not None

    switch_len = normalize_int(row.get("switch"))
    switch_fd = normalize_float(row.get("switch_fd"))
    switch_pass = pass_with_len_fd(switch_fd, switch_len, expected_lengths["switch"])
    switch_fd_present = switch_fd is not None

    # DWI：仅以 FD 为准；FD 有值计总数；通过为 FD<=阈值
    dwi_fd = normalize_float(row.get("dwi_fd"))
    dwi_fd_present = dwi_fd is not None
    dwi_pass = dwi_fd_present and (dwi_fd <= dwi_fd_threshold)

    return {
        "anat_pass": anat_pass,
        "fmap_pass": fmap_pass,
        "rest1_pass": rest1_pass,
        "rest2_pass": rest2_pass,
        "sst_pass": sst_pass,
        "nback_pass": nback_pass,
        "switch_pass": switch_pass,
        "dwi_pass": dwi_pass,
        # 供“是否纳入统计”使用：总计以长度列存在为准
        "rest1_len_present": rest1_len is not None,
        "rest2_len_present": rest2_len is not None,
        "sst_len_present": sst_len is not None,
        "nback_len_present": nback_len is not None,
        "switch_len_present": switch_len is not None,
        # DWI：以 FD 是否存在作为计总依据
        "dwi_fd_present": dwi_fd_present,
        # rest/task：以 FD 是否存在作为计总依据
        "rest1_fd_present": rest1_fd_present,
        "rest2_fd_present": rest2_fd_present,
        "sst_fd_present": sst_fd_present,
        "nback_fd_present": nback_fd_present,
        "switch_fd_present": switch_fd_present,
    }


def summarize_modality(df, group_name, group_mask, modality, expected_lengths, fd_threshold=0.2):
    # 新规则：总数包含该组内的所有个体；NA/空视为失败。
    group_size = int(df.loc[group_mask].shape[0])
    if modality == "anat":
        passes = int((df.loc[group_mask, "anat_pass"]).sum())
        total = group_size
        fails = total - passes
    elif modality == "fmap":
        passes = int((df.loc[group_mask, "fmap_pass"]).sum())
        total = group_size
        fails = total - passes
    else:
        # rest1/rest2/sst/nback/switch：通过为“长度匹配且 FD<=阈值”；
        # DWI：通过为“FD<=阈值”；缺失值（NA/空）均记为失败并计入总数。
        if modality == "dwi":
            passes = int(df.loc[group_mask, "dwi_pass"].sum())
            total = group_size
            fails = total - passes
        else:
            pass_col = f"{modality}_pass"
            passes = int(df.loc[group_mask, pass_col].sum())
            total = group_size
            fails = total - passes

    return {
        "group": group_name,
        "modality": modality,
        "pass": passes,
        "fail": fails,
        "total": total,
    }


def main():
    parser = argparse.ArgumentParser(description="按组统计各模态 QC 通过/失败/合计数量（总数包含所有个体；NA/空视为失败；anat/fmap 通过为 yes；rest/task 通过需长度匹配且FD≤阈值；dwi 通过需FD≤阈值）")
    parser.add_argument(
        "--input",
        default=r"e:\\projects\\neuroimg_pipeline\\datasets\\EFNY\\EFI\\QC_folder\\EFI中期.xlsx",
        help="输入合并后的表格路径（CSV 或 Excel）",
    )
    parser.add_argument(
        "--sheet",
        default=None,
        help="Excel 工作表名称或索引（当输入为 .xlsx/.xls 时有效，默认第一个工作表）",
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
    parser.add_argument(
        "--dwi_fd_threshold",
        type=float,
        default=1.43,
        help="DWI 的 FD 阈值",
    )
    parser.add_argument("--expected_rest1", type=int, default=180, help="rest1 期望长度")
    parser.add_argument("--expected_rest2", type=int, default=180, help="rest2 期望长度")
    parser.add_argument("--expected_sst", type=int, default=161, help="sst 期望长度")
    parser.add_argument("--expected_nback", type=int, default=219, help="nback 期望长度")
    parser.add_argument("--expected_switch", type=int, default=209, help="switch 期望长度")
    # 不再需要头动阈值/长度参数，统计仅基于存在性

    parser.add_argument(
        "--output_group_table",
        default=r"e:\\projects\\neuroimg_pipeline\\datasets\\EFNY\\EFI\\QC_folder\\EFI_QC_group_stats_group_table.csv",
        help="输出分组透视表 CSV（每组的通过/失败/合计/通过率，列为各模态）",
    )

    args = parser.parse_args()

    if not os.path.exists(args.input):
        print(f"输入文件不存在: {args.input}")
        sys.exit(1)

    df, ext = read_table(args.input, args.sheet)
    # df = pd.read_csv(args.input)

    expected_lengths = {
        "rest1": args.expected_rest1,
        "rest2": args.expected_rest2,
        "sst": args.expected_sst,
        "nback": args.expected_nback,
        "switch": args.expected_switch,
    }

    # Compute pass flags for each row（按阈值和期望长度）
    pass_rows = df.apply(lambda r: compute_modality_pass_flags(r, expected_lengths, args.fd_threshold, args.dwi_fd_threshold), axis=1, result_type="expand")
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
    modalities = ["anat", "fmap", "rest1", "rest2", "sst", "nback", "switch", "dwi"]

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
    out_df.to_csv(args.output, index=False, encoding="utf-8-sig")

    # 生成“按组呈现”的透视表（不包含 anat/fmap；包含 dwi）
    def build_group_table(out_df, groups_order, modality_pairs):
        rows = []
        for grp in groups_order + ["ALL"]:
            # 收集每个模态的 pass/fail/total
            stats = {}
            for internal_name, display_name in modality_pairs:
                row = out_df[(out_df.group == grp) & (out_df.modality == internal_name)].iloc[0]
                stats[display_name] = {
                    "pass": int(row["pass"]),
                    "fail": int(row["fail"]),
                    "total": int(row["total"]),
                }

            # 通过、失败、合计、通过率四行
            pass_row = {"group": grp, "metric": "通过"}
            fail_row = {"group": grp, "metric": "失败"}
            total_row = {"group": grp, "metric": "合计"}
            rate_row = {"group": grp, "metric": "通过率"}
            for _, display_name in modality_pairs:
                s = stats[display_name]
                pass_row[display_name] = s["pass"]
                fail_row[display_name] = s["fail"]
                total_row[display_name] = s["total"]
                if s["total"] > 0:
                    rate_row[display_name] = f"{(s['pass'] / s['total']) * 100:.2f}%"
                else:
                    rate_row[display_name] = ""  # 无样本不显示比例
            rows.extend([pass_row, fail_row, total_row, rate_row])
        return pd.DataFrame(rows)

    modality_pairs = [("rest1", "rest_1"), ("rest2", "rest_2"), ("sst", "sst"), ("switch", "switch"), ("nback", "nback"), ("dwi", "dwi")]
    group_table = build_group_table(out_df, groups, modality_pairs)
    group_table.to_csv(args.output_group_table, index=False, encoding="utf-8-sig")

    # Also print a readable summary
    print("分组透视表（rest/task 以 FD 存在计总数；dwi 以 FD 存在计总数）：")
    for grp in groups + ["ALL"]:
        print(f"\n{grp}")
        # 打印四行：通过、失败、合计、通过率
        for metric in ["通过", "失败", "合计", "通过率"]:
            row = group_table[(group_table.group == grp) & (group_table.metric == metric)].iloc[0]
            values = " | ".join([f"{col} {row[col]}" for col in [p[1] for p in modality_pairs]])
            print(values)


if __name__ == "__main__":
    main()