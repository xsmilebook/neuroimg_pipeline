import argparse
import os
import sys
import pandas as pd


def _read_table(path):
    ext = os.path.splitext(path)[1].lower()
    try:
        if ext in [".xlsx", ".xls"]:
            return pd.read_excel(path)
        return pd.read_csv(path)
    except Exception as e:
        print(f"读取表失败: {path} -> {e}")
        sys.exit(1)


def _normalize_id(val):
    if pd.isna(val):
        return None
    s = str(val).strip()
    return s if s != "" else None


def _dedupe_group(df, id_col, group_col):
    # 规范化 ID
    df = df.copy()
    df[id_col] = df[id_col].apply(_normalize_id)
    # 只保留 id 存在的行
    df = df[df[id_col].notna()]

    # 对重复 ID：优先选择首个非空 Group
    # 构造辅助列标记非空
    df["__group_nonempty__"] = ~df[group_col].isna()
    # 按非空优先、原始顺序稳定选择
    df_sorted = df.sort_values(by=["__group_nonempty__"], ascending=False)
    df_dedup = df_sorted.drop_duplicates(subset=[id_col], keep="first")
    df_dedup = df_dedup[[id_col, group_col]].copy()
    return df_dedup


def merge_group(main_path,
                group_path,
                main_id="subj_ID",
                group_id="subject_name",
                group_col="Group",
                output_path=None,
                group_extra_output_path=None,
                unmatched_output_path=None,
                overwrite=False):
    if not os.path.exists(main_path):
        print(f"主表不存在: {main_path}")
        sys.exit(1)
    if not os.path.exists(group_path):
        print(f"分组表不存在: {group_path}")
        sys.exit(1)

    main_df = _read_table(main_path)
    group_df_raw = _read_table(group_path)

    # 基本列校验
    for col, pth in [(main_id, main_path), (group_id, group_path), (group_col, group_path)]:
        if col not in (main_df.columns if pth == main_path else group_df_raw.columns):
            print(f"错误: 文件 {pth} 缺少列 {col}")
            sys.exit(1)

    # 规范化 ID
    main_df = main_df.copy()
    main_df[main_id] = main_df[main_id].apply(_normalize_id)
    group_df_raw = group_df_raw.copy()
    group_df_raw[group_id] = group_df_raw[group_id].apply(_normalize_id)

    # 去重并取首个非空 Group
    group_df = _dedupe_group(group_df_raw, group_id, group_col)

    # 合并（左连接，带指示列标记是否按ID匹配）
    merged = main_df.merge(
        group_df,
        how="left",
        left_on=main_id,
        right_on=group_id,
        indicator=True,
    )

    # 处理已存在 Group 列的情况
    out_group_col = group_col
    if group_col in main_df.columns:
        # 主表已有 Group，右表的 Group 会以默认后缀 _y 出现
        right_name = f"{group_col}_y"
        if right_name in merged.columns:
            out_group_col = f"{group_col}"
            merged = merged.rename(columns={right_name: out_group_col})
    elif group_col in merged.columns:
        # 主表没有 Group，右表的 Group 直接作为输出列
        out_group_col = group_col

    # 删除右侧 ID 辅助列
    if group_id in merged.columns:
        merged = merged.drop(columns=[group_id])

    # 输出路径
    if output_path is None:
        base_dir = os.path.dirname(main_path)
        base_name = os.path.splitext(os.path.basename(main_path))[0]
        output_path = os.path.join(base_dir, f"{base_name}_with_group.csv")
    # 分组表独有ID输出路径（在分组表有但主表没有）
    if group_extra_output_path is None:
        base_dir_group = os.path.dirname(group_path)
        base_name_group = os.path.splitext(os.path.basename(group_path))[0]
        group_extra_output_path = os.path.join(base_dir_group, f"{base_name_group}_IDs_not_in_main.csv")
    # 未匹配ID输出路径
    if unmatched_output_path is None:
        base_dir_unmatched = os.path.dirname(output_path) if output_path else os.path.dirname(main_path)
        base_name_main = os.path.splitext(os.path.basename(main_path))[0]
        unmatched_output_path = os.path.join(base_dir_unmatched, f"{base_name_main}_unmatched_ids.csv")

    # 统计信息（按ID是否匹配，不以Group是否为空判断）
    total_main = merged.shape[0]
    matched_by_id = int((merged["_merge"] == "both").sum())
    nonempty_group = int(merged.loc[merged["_merge"] == "both", out_group_col].notna().sum())
    empty_group = matched_by_id - nonempty_group
    unmatched = int((merged["_merge"] == "left_only").sum())
    print(
        f"总行数: {total_main} | 按ID匹配: {matched_by_id} (Group非空: {nonempty_group}, 空/NA: {empty_group}) | 未匹配: {unmatched}"
    )

    # 统计与输出：分组表存在但主表不存在的ID
    main_ids_series = main_df[main_id].dropna()
    group_extra_mask = ~group_df[group_id].isin(main_ids_series)
    group_extra_df = group_df.loc[group_extra_mask, [group_id]].copy()
    extra_count = group_extra_df.shape[0]
    if extra_count > 0:
        out_dir_group_extra = os.path.dirname(group_extra_output_path)
        if out_dir_group_extra and not os.path.exists(out_dir_group_extra):
            os.makedirs(out_dir_group_extra, exist_ok=True)
        group_extra_df.to_csv(group_extra_output_path, index=False, encoding="utf-8-sig")
        preview_ct2 = min(10, extra_count)
        preview_vals2 = ", ".join(map(str, group_extra_df[group_id].head(preview_ct2).tolist()))
        print(f"分组表独有ID数: {extra_count} | 已保存: {group_extra_output_path} | 示例({preview_ct2}): {preview_vals2}")
    else:
        print("分组表与主表ID集合一致，无分组表独有ID。")

    # 输出未匹配ID列表
    if unmatched > 0:
        unmatched_df = merged.loc[merged["_merge"] == "left_only", [main_id]].copy()
        unmatched_df = unmatched_df.rename(columns={main_id: main_id})
        out_dir_unmatched = os.path.dirname(unmatched_output_path)
        if out_dir_unmatched and not os.path.exists(out_dir_unmatched):
            os.makedirs(out_dir_unmatched, exist_ok=True)
        unmatched_df.to_csv(unmatched_output_path, index=False, encoding="utf-8-sig")
        # 预览前10条
        preview_ct = min(10, unmatched)
        preview_vals = ", ".join(map(str, unmatched_df[main_id].head(preview_ct).tolist()))
        print(f"未匹配ID已保存: {unmatched_output_path} | 示例({preview_ct}): {preview_vals}")
    else:
        print("所有ID均已匹配，无未匹配项。")

    # 清理合并指示列
    if "_merge" in merged.columns:
        merged = merged.drop(columns=["_merge"]) 

    # 保存
    out_dir = os.path.dirname(output_path)
    if out_dir and not os.path.exists(out_dir):
        os.makedirs(out_dir, exist_ok=True)
    merged.to_csv(output_path, index=False, encoding="utf-8-sig")
    print(f"已保存: {output_path}")

    # 可选覆盖主表
    if overwrite:
        merged.to_csv(main_path, index=False, encoding="utf-8-sig")
        print(f"已覆盖主表: {main_path}")


def main():
    parser = argparse.ArgumentParser(description="将分组表(Group)按 subject_name 合并至主表(subj_ID)")
    parser.add_argument(
        "--main",
        default=r"e:\\projects\\neuroimg_pipeline\\datasets\\EFNY\\THU\\QC_folder\\THU_QC_merged.csv",
        help="主表路径（包含 subj_ID 列）",
    )
    parser.add_argument(
        "--group",
        default=r"e:\\projects\\neuroimg_pipeline\\datasets\\EFNY\\THU\\QC_folder\\QC_with_demographics_1112.csv",
        help="分组表路径（包含 subject_name 与 Group 列）",
    )
    parser.add_argument("--main_id", default="subj_ID", help="主表 ID 列名")
    parser.add_argument("--group_id", default="subject_name", help="分组表 ID 列名")
    parser.add_argument("--group_col", default="Group", help="分组列名")
    parser.add_argument("--output", default="", help="输出 CSV 路径（默认与主表同目录 *_with_group.csv）")
    parser.add_argument("--group_extra_output", default="", help="分组表存在但主表不存在的ID输出路径（默认与分组表同目录 *_IDs_not_in_main.csv）")
    parser.add_argument("--unmatched_output", default="", help="未匹配ID输出路径（默认与输出同目录 *_unmatched_ids.csv）")
    parser.add_argument("--overwrite", action="store_true", help="是否覆盖主表（默认否）")

    args = parser.parse_args()

    output_path = args.output if args.output else None
    group_extra_output_path = args.group_extra_output if args.group_extra_output else None
    unmatched_output_path = args.unmatched_output if args.unmatched_output else None
    merge_group(
        main_path=args.main,
        group_path=args.group,
        main_id=args.main_id,
        group_id=args.group_id,
        group_col=args.group_col,
        output_path=output_path,
        group_extra_output_path=group_extra_output_path,
        unmatched_output_path=unmatched_output_path,
        overwrite=args.overwrite,
    )


if __name__ == "__main__":
    main()