# slack2backlog 開発環境セットアップガイド

## 概要

このドキュメントでは、slack2backlogプロジェクトの開発に必要なツールのインストール手順を説明します。

## 前提条件

- Ubuntu/Debian系Linux または WSL2
- インターネット接続
- sudo権限

## インストール済み確認

まず、既にインストールされているツールを確認します：

```bash
# Node.js
node --version  # v20.x以上が必要

# Python
python3 --version  # 3.12以上が必要

# Git
git --version

# パッケージマネージャー
npm --version
pip --version
```

## 1. システムパッケージの更新

```bash
sudo apt update
sudo apt upgrade -y
```

## 2. AWS CLI v2のインストール

AWS CLI v2は公式インストーラーを使用します：

```bash
# ダウンロードと解凍
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip

# インストール
sudo ./aws/install

# クリーンアップ
rm -rf awscliv2.zip aws/

# 確認
aws --version
```

期待される出力: `aws-cli/2.x.x Python/3.x.x Linux/x.x.x exe/x86_64.ubuntu.xx`

## 3. AWS SAM CLIのインストール

### 方法1: 公式インストーラー（推奨）

```bash
# ダウンロード
wget https://github.com/aws/aws-sam-cli/releases/latest/download/aws-sam-cli-linux-x86_64.zip

# 解凍
unzip aws-sam-cli-linux-x86_64.zip -d sam-installation

# インストール
sudo ./sam-installation/install

# クリーンアップ
rm -rf aws-sam-cli-linux-x86_64.zip sam-installation/

# 確認
sam --version
```

### 方法2: Homebrewを使用（Homebrewがインストール済みの場合）

```bash
brew install aws-sam-cli
```

## 4. AWS CDKのインストール

npmを使用してグローバルにインストール：

```bash
sudo npm install -g aws-cdk

# 確認
cdk --version
```

## 5. Jestのインストール（JavaScriptテストフレームワーク）

```bash
sudo npm install -g jest

# 確認
jest --version
```

## 6. pytestのインストール（Pythonテストフレームワーク）

### 方法1: pipxを使用（推奨）

```bash
# pipxのインストール
sudo apt update
sudo apt install pipx -y
pipx ensurepath

# 新しいターミナルを開くか、以下を実行
source ~/.bashrc

# pytestのインストール
pipx install pytest

# 確認
pytest --version
```

### 方法2: aptパッケージを使用

```bash
sudo apt install python3-pytest -y

# 確認
pytest --version
```

## 7. GitHub CLI (gh)のインストール

### 公式リポジトリから最新版をインストール

```bash
# GPGキーの追加
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg

# リポジトリの追加
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

# インストール
sudo apt update
sudo apt install gh -y

# 確認
gh --version
```

## 8. 追加の推奨ツール

### jqのインストール（JSONパーサー）

```bash
sudo apt install jq -y
```

### yqのインストール（YAMLパーサー）

```bash
sudo snap install yq
```

## インストール確認スクリプト

すべてのツールが正しくインストールされたか確認するスクリプト：

```bash
#!/bin/bash

echo "=== slack2backlog Development Environment Check ==="
echo

# 色の定義
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# チェック関数
check_command() {
    if command -v $1 &> /dev/null; then
        version=$($2 2>&1)
        echo -e "${GREEN}✓${NC} $1: $version"
    else
        echo -e "${RED}✗${NC} $1: Not installed"
    fi
}

# 各ツールのチェック
check_command "node" "node --version"
check_command "npm" "npm --version"
check_command "python3" "python3 --version"
check_command "pip" "pip --version"
check_command "git" "git --version"
check_command "aws" "aws --version | head -n1"
check_command "sam" "sam --version"
check_command "cdk" "cdk --version"
check_command "jest" "jest --version"
check_command "pytest" "pytest --version | head -n1"
check_command "gh" "gh --version | head -n1"
check_command "jq" "jq --version"
check_command "yq" "yq --version"

echo
echo "=== Check Complete ==="
```

上記のスクリプトを `check-env.sh` として保存し、実行権限を付与して実行：

```bash
chmod +x check-env.sh
./check-env.sh
```

## トラブルシューティング

### 1. Permission denied エラー

```bash
# npmグローバルインストール時のエラーの場合
sudo npm install -g <package-name>
```

### 2. Python パッケージインストールエラー

```
error: externally-managed-environment
```

このエラーが出る場合は、pipxを使用するか、仮想環境を作成してください。

### 3. AWS CLIが見つからない

```bash
# PATHに追加
echo 'export PATH=$PATH:/usr/local/bin' >> ~/.bashrc
source ~/.bashrc
```

### 4. SAM CLIのPython依存関係エラー

SAM CLIは内部でPythonを使用します。Python 3.8以上が必要です。

### 5. CDKの初回実行時

```bash
# CDKブートストラップ（初回のみ）
cdk bootstrap aws://ACCOUNT-NUMBER/REGION
```

## AWS認証設定

インストール完了後、AWS CLIの認証設定を行います：

```bash
aws configure
```

以下の情報が必要です：
- AWS Access Key ID
- AWS Secret Access Key
- Default region name (例: ap-northeast-1)
- Default output format (例: json)

## 次のステップ

1. プロジェクトのクローン
   ```bash
   git clone https://github.com/bridge-nakao/slack2backlog.git
   cd slack2backlog
   ```

2. プロジェクト依存関係のインストール
   ```bash
   npm install
   # または
   pip install -r requirements.txt
   ```

3. 開発開始！

## 参考リンク

- [AWS CLI Documentation](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [AWS SAM CLI Documentation](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-cli-install.html)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/v2/guide/getting_started.html)
- [Jest Documentation](https://jestjs.io/docs/getting-started)
- [pytest Documentation](https://docs.pytest.org/en/stable/getting-started.html)
- [GitHub CLI Documentation](https://cli.github.com/manual/)