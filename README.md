# An Cư (AnCu)

Dự án được xây dựng theo phương pháp **Vibe Coding** phối hợp cùng **Claude Code**.

## Cấu trúc thư mục
- `CLAUDE.md`: File cấu hình chỉ dẫn trọng tâm cho Claude Code khi mở session.
- `docs/01-ideas/`: Brainstorm ý tưởng thô và PRD.
- `docs/02-specs/`: Kiến trúc kỹ thuật, schema dữ liệu và API design.
- `docs/03-plans/`: Kế hoạch thực hiện từng bước nhỏ (atomic tasks).
- `docs/04-tracking/`: Quản lý tiến độ (`tasks.md`) và nhật ký session (`devlog.md`).
- `src/`: Mã nguồn ứng dụng.
- `tests/`: Bộ kiểm thử.

## Bắt đầu làm việc với Claude Code
1. Mở terminal tại thư mục này:
   ```bash
   cd /Users/lequocdien/Downloads/AnCu
   ```
2. Khởi động Claude Code:
   ```bash
   claude
   ```
3. Prompt mẫu để bắt đầu:
   > *"Đọc file `CLAUDE.md` và kiểm tra `docs/04-tracking/tasks.md`. Hãy cho tôi biết bước tiếp theo chúng ta cần làm gì."*
