import argparse
import os
import sys
import pandas as pd

def _parse_sheet_arg(sheet_arg):
    if sheet_arg is None:
        return 0  # 默认取第一个工作表
    s = str(sheet_arg).strip()
    return int(s) if s.isdigit() else s


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

def normalize_float(val):
    if pd.isna(val):
        return None
    s = str(val).strip()
    if s == "" or s.lower() in {"na", "n/a", "nan"}:
        return None
    try:
        return float(s)
    except Exception:
        try:
            return float(s.replace(",", ""))
        except Exception:
            return None


def assign_group_flags(group_str):
    # Group 列为分组字符串信息；大小写不敏感
    if pd.isna(group_str):
        s = ""
    else:
        s = str(group_str).strip()
    s_upper = s.upper()

    is_adhd = "ADHD" in s_upper
    only_adhd = is_adhd and ("DDC" not in s_upper) and ("DD" not in s_upper)
    is_non_adhd = not is_adhd
    is_ddc = "DDC" in s_upper
    # DD：出现 DD，但不能出现 MD
    is_dd = ("DD" in s_upper) and ("DDC" not in s_upper)
    # TD：出现 NA 或者为空
    is_td = ("NA" in s_upper) or (s_upper == "") or (s_upper == "N/A")

    return {
        "ADHD": only_adhd,
        "非ADHD": is_non_adhd,
        "DDC": is_ddc,
        "DD": is_dd,
        "TD": is_td,
    }


def compute_fd_pass_flags(row, fd_cols, fd_threshold=0.2, dwi_fd_threshold=1.43):
    results = {}
    for internal_name, csv_col in fd_cols.items():
        fd_val = normalize_float(row.get(csv_col))
        fd_present = fd_val is not None
        # dwi 使用单独阈值，其它模态使用通用阈值
        thr = dwi_fd_threshold if internal_name == "dwi" else fd_threshold
        fd_pass = fd_present and (fd_val <= thr)
        results[f"{internal_name}_fd_present"] = fd_present
        results[f"{internal_name}_pass"] = fd_pass
    return results


def summarize_modality(df, group_name, group_mask, internal_name):
    fd_present_col = f"{internal_name}_fd_present"
    pass_col = f"{internal_name}_pass"
    considered = df.loc[group_mask & (df[fd_present_col] == True)]
    total = int(considered.shape[0])
    passes = int(considered[pass_col].sum())
    fails = total - passes
    return {
        "group": group_name,
        "modality": internal_name,
        "pass": passes,
        "fail": fails,
        "total": total,
    }


def build_group_table(out_df, groups_order, modality_pairs):
    rows = []
    for grp in groups_order + ["ALL"]:
        stats = {}
        for internal_name, display_name in modality_pairs:
            row = out_df[(out_df.group == grp) & (out_df.modality == internal_name)].iloc[0]
            stats[display_name] = {
                "pass": int(row["pass"]),
                "fail": int(row["fail"]),
                "total": int(row["total"]),
            }

        pass_row = {"group": grp, "metric": "通过"}
        fail_row = {"group": grp, "metric": "失败"}
        total_row = {"group": grp, "metric": "合计"}
        rate_row = {"group": grp, "metric": "通过率"}
        for _, display_name in modality_pairs:
            s = stats[display_name]
            pass_row[display_name] = s["pass"]
            fail_row[display_name] = s["fail"]
            total_row[display_name] = s["total"]
            rate_row[display_name] = f"{(s['pass'] / s['total']) * 100:.2f}%" if s["total"] > 0 else ""
        rows.extend([pass_row, fail_row, total_row, rate_row])
    return pd.DataFrame(rows)


def main():
    parser = argparse.ArgumentParser(description="基于新表格（CSV/XLSX，FD 列）按组统计任务与 DWI 的通过/失败/合计/通过率；总数仅统计有 FD 的个体，失败为有 FD 但未通过")
    parser.add_argument(
        "--input",
        default=r"e:\\projects\\neuroimg_pipeline\\datasets\\EFNY\\XY\\xy_fd.xlsx",
        help="输入 CSV/XLSX 路径（包含列：Group, dwi, T1w, T2w, nback, rest_1, rest_2, rest_3, rest_4, sst, switch）",
    )
    parser.add_argument(
        "--sheet",
        default=None,
        help="Excel 工作表名称或索引（当输入为 .xlsx/.xls 时有效，默认第一个工作表）",
    )
    parser.add_argument(
        "--output",
        default=r"e:\\projects\\neuroimg_pipeline\\datasets\\EFNY\\QC_all\\XY_QC_group_stats_new_long.csv",
        help="输出长表统计 CSV（group+modality 行）",
    )
    parser.add_argument(
        "--output_group_table",
        default=r"e:\\projects\\neuroimg_pipeline\\datasets\\EFNY\\EFI\\QC_all\\XY_QC_group_stats_new_group_table.csv",
        help="输出分组透视表 CSV（每组：通过/失败/合计/通过率；列为各任务）",
    )
    parser.add_argument(
        "--fd_threshold",
        type=float,
        default=0.2,
        help="任务 FD 阈值（通过条件：FD<=阈值）",
    )
    parser.add_argument(
        "--dwi_fd_threshold",
        type=float,
        default=1.43,
        help="DWI FD 阈值（通过条件：FD<=阈值）",
    )
    parser.add_argument(
        "--save_csv",
        default="",
        help="可选：若输入为 xlsx/xls，读取后另存为此 CSV 路径以便复用",
    )

    args = parser.parse_args()

    if not os.path.exists(args.input):
        print(f"输入文件不存在: {args.input}")
        sys.exit(1)

    df, ext = read_table(args.input, args.sheet)
    # 若需要把 Excel 转存为 CSV
    if ext in [".xlsx", ".xls"] and args.save_csv:
        out_dir_csv = os.path.dirname(args.save_csv)
        if out_dir_csv and not os.path.exists(out_dir_csv):
            os.makedirs(out_dir_csv, exist_ok=True)
        df.to_csv(args.save_csv, index=False)

    # 任务模态列映射：内部名 → CSV 列名（仅统计这些）
    fd_cols = {
        "rest1": "rest_1",
        "rest2": "rest_2",
        "rest3": "rest_3",
        "sst": "sst",
        "switch": "switch",
        "nback": "nback",
        "dwi": "dwi",
    }

    # 校验列是否存在，缺失则补空列并告警
    for csv_col in fd_cols.values():
        if csv_col not in df.columns:
            print(f"警告：输入表缺少列 {csv_col}，该模态的总数将为 0。")
            df[csv_col] = pd.NA

    # 计算每行的 FD 存在与通过标记
    fd_flags = df.apply(lambda r: compute_fd_pass_flags(r, fd_cols, args.fd_threshold, args.dwi_fd_threshold), axis=1, result_type="expand")
    for col in fd_flags.columns:
        df[col] = fd_flags[col]

    # 分组标记（基于 Group 字段）
    if "Group" not in df.columns:
        print("错误：输入表缺少 Group 列。")
        sys.exit(1)
    group_flags = df["Group"].apply(assign_group_flags)
    group_df = pd.DataFrame(group_flags.tolist())
    for col in group_df.columns:
        df[f"group_{col}"] = group_df[col]

    groups = ["ADHD", "非ADHD", "DDC", "DD", "TD"]
    modalities = list(fd_cols.keys())

    # 汇总
    summaries = []
    for group in groups:
        group_mask = df[f"group_{group}"] == True
        for modality in modalities:
            summaries.append(summarize_modality(df, group, group_mask, modality))

    # ALL 组
    all_mask = pd.Series([True] * df.shape[0], index=df.index)
    for modality in modalities:
        summaries.append(summarize_modality(df, "ALL", all_mask, modality))

    out_df = pd.DataFrame(summaries, columns=["group", "modality", "pass", "fail", "total"])

    # 保存长表
    out_dir = os.path.dirname(args.output)
    if out_dir and not os.path.exists(out_dir):
        os.makedirs(out_dir, exist_ok=True)
    out_df.to_csv(args.output, index=False)

    # 生成分组透视表（列为显示名）
    modality_pairs = [("rest1", "rest_1"), ("rest2", "rest_2"), ("rest3", "rest_3"), ("sst", "sst"), ("switch", "switch"), ("nback", "nback"), ("dwi", "dwi")]
    group_table = build_group_table(out_df, groups, modality_pairs)

    out_dir2 = os.path.dirname(args.output_group_table)
    if out_dir2 and not os.path.exists(out_dir2):
        os.makedirs(out_dir2, exist_ok=True)
    group_table.to_csv(args.output_group_table, index=False, encoding="utf-8-sig")

    # 控制台打印分组块
    print("分组透视表（总数仅统计有 FD 的个体；失败为有 FD 但未通过；含 DWI）：")
    for grp in groups + ["ALL"]:
        print(f"\n{grp}")
        for metric in ["通过", "失败", "合计", "通过率"]:
            row = group_table[(group_table.group == grp) & (group_table.metric == metric)].iloc[0]
            values = " | ".join([f"{col} {row[col]}" for col in [p[1] for p in modality_pairs]])
            print(values)


if __name__ == "__main__":
    main()