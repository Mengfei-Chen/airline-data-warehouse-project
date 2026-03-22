import pandas as pd

# 1. 读取 CSV
df = pd.read_csv("association_mining_input.csv")

# 2. 查看基本信息
print("Shape:", df.shape)
print("\nColumns:")
print(df.columns.tolist())

print("\nFirst 5 rows:")
print(df.head())

print("\nMissing values per column:")
print(df.isnull().sum())

print("\nUnique values count per selected column:")
for col in ["gender", "age_group", "nationality", "continent_name", "month_name", "flight_status"]:
    print(f"{col}: {df[col].nunique()}")