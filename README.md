# NSLinuxFiles: Extreme Performance para Nintendo Switch

Este repositório contém uma suíte de automação projetada para transformar o Nintendo Switch (Tegra X1) rodando **L4T Linux Jammy** em uma estação de emulação de alta performance, otimizada especificamente para o **Dolphin Emulator**.

---

## ⚠️ AVISO DE ISENÇÃO DE RESPONSABILIDADE (DISCLAIMER)

**ESTE SOFTWARE É FORNECIDO "COMO ESTÁ", SEM GARANTIA DE QUALQUER TIPO.**

*   **Uso por Conta e Risco**: A execução deste setup e o uso de overclocking podem invalidar a garantia do seu hardware, aumentar o desgaste da bateria e, em casos extremos, causar danos físicos ao console por estresse térmico.
*   **Responsabilidade**: O usuário assume total responsabilidade por quaisquer consequências resultantes do uso deste script.
*   **Isenção**: O autor não se responsabiliza por danos, perdas de dados, banimentos de serviços online ou falhas de hardware decorrentes das modificações aplicadas.
*   **Segurança**: Este script altera parâmetros do Kernel e privilégios de sistema (`sudoers`) para permitir o controle de hardware em tempo real.

---

## 📋 Premissa de Instalação

Para que o setup funcione corretamente, você deve cumprir os seguintes requisitos:

1.  **Sistema Operacional**: Deve estar utilizando o **L4T Linux Ubuntu Jammy 22.04**.
2.  **Guia de Origem**: O Linux deve ter sido instalado seguindo o [Guia Oficial da Switchroot](https://wiki.switchroot.org/wiki/linux/l4t-ubuntu-jammy-installation-guide).
3.  **Hardware**: Nintendo Switch desbloqueado (v1, v2 ou OLED).
4.  **Internet**: Conexão ativa para download das dependências e do emulador.

---

## 🚀 Instalação Rápida (One-Liner)

Abra o terminal no seu Switch e cole o comando abaixo para iniciar o instalador automatizado:

```bash
curl -sSL [https://raw.githubusercontent.com/antonio-leonardo/NSLinuxFiles/main/setup.sh](https://raw.githubusercontent.com/antonio-leonardo/NSLinuxFiles/main/setup.sh) | bash