using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Management;
using System.Threading;
using System.Windows.Forms;

namespace GmsMode
{
    internal class Snapshot
    {
        public List<Entry> Entries;
        public readonly List<string> Notes = new List<string>();
        public List<string> Processes;
        public string[] Roots;
        public string Boot = "";
        public Journal Journal;
        public string JournalError = "";
        public bool LegacyVisibleCandidate;
        public readonly List<string> Saved = new List<string>();
        public static string BootId()
        {
            using (var q = new ManagementObjectSearcher("SELECT LastBootUpTime FROM Win32_OperatingSystem"))
            using (var set = q.Get())
                foreach (ManagementObject obj in set) using (obj) return Convert.ToString(obj["LastBootUpTime"]);
            return "";
        }
        public static Snapshot Scan(string[] extra, Disk disk, bool elevated)
        {
            var s = new Snapshot();
            s.LegacyVisibleCandidate = LegacyWindow.Found();
            if (s.LegacyVisibleCandidate) s.Notes.Add("v2 창이 열려 있습니다. 'v2 창 표시'를 누르고 기존 창을 정상적으로 닫은 후 전환하세요.");
            try { s.Boot = BootId(); }
            catch { s.Notes.Add("Windows의 마지막 부팅 시각을 조회할 수 없습니다."); }
            if (elevated)
            {
                try { s.Journal = disk.Load(); }
                catch (Exception ex) { s.JournalError = ex.Message; s.Notes.Add("복구 기록 확인 필요 · " + ex.Message); }
            }
            var remembered = s.Journal == null ? new string[0] : s.Journal.Roots;
            s.Roots = RuntimeOps.Discover(s.Notes).Concat(extra).Concat(remembered)
                .Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(p => p, StringComparer.OrdinalIgnoreCase).ToArray();
            var system = new WindowsEntries(s.Roots);
            s.Entries = system.Scan(s.Notes);
            s.Processes = RuntimeOps.Inspect(s.Roots, s.Notes);
            if (s.Journal != null)
                foreach (var e in s.Journal.Owned)
                {
                    string state;
                    try { string now = system.Read(e); state = now == e.After ? "차단 상태" : now == e.Before ? "원래 상태" : "충돌"; }
                    catch { state = "확인 필요"; }
                    s.Saved.Add(state + "    " + e.Label);
                }
            return s;
        }
    }

    internal sealed class Dashboard : Form
    {
        readonly bool elevated;
        readonly Disk disk = new Disk(Disk.Production, true);
        readonly List<string> extra = new List<string>();
        readonly ListView entries = new ListView();
        readonly TextBox runtime = TextPanel(), recovery = TextPanel();
        readonly FlowLayoutPanel actions = new FlowLayoutPanel(), tools = new FlowLayoutPanel();
        readonly Label status = new Label();
        readonly Button scan = new Button(), apply = new Button(), restore = new Button(), undo = new Button(), showLegacy = new Button();
        Snapshot snapshot;
        bool busy;
        static readonly Color Ink = Color.FromArgb(28,46,68), Blue = Color.FromArgb(35,76,115);
        string initialReview;
        internal Dashboard(bool isElevated, string review)
        {
            elevated = isElevated;
            initialReview = review;
            Text = "GMS Operating Mode 3.0.1"; Font = new Font("Malgun Gothic", 9);
            AutoScaleMode = AutoScaleMode.Dpi; StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(1016, 664); MinimumSize = new Size(720, 530);
            BackColor = Color.FromArgb(244,246,249);
            var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(18,12,18,10), ColumnCount = 1, RowCount = 6 };
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
            foreach (var size in new[]{43,35,0,0,0,22})
                layout.RowStyles.Add(size == 0 ? new RowStyle(SizeType.AutoSize) : new RowStyle(SizeType.Absolute,size));
            layout.RowStyles[3] = new RowStyle(SizeType.Percent,100);
            Controls.Add(layout);
            layout.Controls.Add(new Label { Text = "GMS  |  OPERATING MODE", Font = new Font(Font.FontFamily,19,FontStyle.Bold),
                ForeColor = Ink, AutoSize = true, Anchor = AnchorStyles.Left },0,0);
            status.Dock = DockStyle.Fill; status.TextAlign = ContentAlignment.MiddleLeft; status.AutoEllipsis = true;
            status.ForeColor = Blue; status.Font = new Font(Font.FontFamily,10,FontStyle.Bold); layout.Controls.Add(status,0,1);
            Bar(layout,actions,2);
            Add(actions,apply,"수동 모드 전환",delegate { Change(true); });
            apply.BackColor = Blue; apply.ForeColor = Color.White;
            Add(actions,restore,"기존 모드 복원",delegate { Change(false); });
            Add(actions,undo,"중단된 작업 복구",Recover);
            Add(actions,scan,"다시 검사",RefreshScan);
            if (!elevated) Add(actions,new Button(),"관리자 권한으로 열기",Elevate);
            var tabs = new TabControl { Dock = DockStyle.Fill, Padding = new Point(14,6) };
            layout.Controls.Add(tabs,0,3);
            entries.Dock = DockStyle.Fill; entries.FullRowSelect = true; entries.View = View.Details;
            entries.GridLines = true; entries.HideSelection = false; entries.ShowItemToolTips = true;
            entries.Columns.Add("판정",90); entries.Columns.Add("시작 항목",237); entries.Columns.Add("예정 변경",230); entries.Columns.Add("식별 근거",380);
            Tab(tabs,"자동 실행",entries); Tab(tabs,"실행 상태 · 확인 필요",runtime); Tab(tabs,"백업 · 복구",recovery);
            entries.DoubleClick += delegate {
                if (entries.SelectedItems.Count != 1) return;
                var e = (Entry)entries.SelectedItems[0].Tag;
                if (e == null) return;
                Review("시작 항목 상세", e.Label + "\r\n" + e.Change + "\r\n\r\n" + e.Proof + "\r\n" + e.Details, false);
            };
            Bar(layout,tools,4);
            Add(tools,new Button(),"Host 정상 종료",Shutdown);
            Add(tools,new Button(),"Host 수동 시작",Start);
            Add(tools,new Button(),"작업 스케줄러",delegate { Process.Start(Path.Combine(Environment.SystemDirectory,"mmc.exe"),Path.Combine(Environment.SystemDirectory,"taskschd.msc")); });
            Add(tools,new Button(),"서버 폴더 추가",AddRoot);
            Add(tools,new Button(),"안전 종료 안내",Guide);
            Add(tools,showLegacy,"v2 창 표시",delegate {
                if (!LegacyWindow.Reveal()) MessageBox.Show(this,"기존 창을 표시하지 못했습니다. 같은 계정의 관리자 모드에서 다시 확인하세요.",Text);
            });
            showLegacy.Visible = false;
            layout.Controls.Add(new Label { AutoSize = true, ForeColor = Blue,
                Text = elevated ? "관리자 모드   ·   적용 전 변경 목록과 복구 기록을 확인하세요." : "조회 모드   ·   운영 설정을 변경하려면 같은 계정으로 관리자 권한을 승인하세요." },0,5);
            Shown += delegate { RefreshScan(); };
            FormClosing += delegate(object sender, FormClosingEventArgs e) {
                if (busy && e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; status.Text = "현재 작업이 끝나면 창을 닫을 수 있습니다."; }
            };
        }
        static TextBox TextPanel() { return new TextBox { Dock = DockStyle.Fill, Multiline = true, ReadOnly = true,
            ScrollBars = ScrollBars.Vertical, WordWrap = true, BackColor = Color.White, BorderStyle = BorderStyle.None }; }
        static void Tab(TabControl tabs,string title,Control child)
        {
            var page = new TabPage(title) { Padding = new Padding(7), BackColor = Color.White };
            page.Controls.Add(child); tabs.TabPages.Add(page);
        }
        static void Bar(TableLayoutPanel layout,FlowLayoutPanel bar,int row)
        {
            bar.Dock = DockStyle.Fill; bar.AutoSize = true; bar.WrapContents = true;
            bar.Margin = new Padding(0,4,0,5); layout.Controls.Add(bar,0,row);
        }
        void Add(FlowLayoutPanel parent,Button b,string text,Action action)
        {
            b.AutoSize = true; b.Text = text; b.Padding = new Padding(8,4,8,4); b.BackColor = Color.White;
            b.FlatStyle = FlatStyle.Flat; b.FlatAppearance.BorderColor = Color.FromArgb(190,199,209);
            b.Click += delegate { try { action(); } catch (Exception ex) { Log.Failure(text,ex); } };
            parent.Controls.Add(b);
        }
        void Elevate() { if (Program.Elevate()) Close(); }
        bool Ready() { if (!elevated) { Elevate(); return false; } return snapshot != null && !busy; }
        void SetBusy(bool value)
        {
            busy = value; actions.Enabled = !value; tools.Enabled = !value; UseWaitCursor = value;
        }
        void Work(string title,Action action,Action done)
        {
            if (busy) return;
            SetBusy(true); status.Text = title;
            var worker = new Thread(delegate() {
                Exception failure = null;
                try { action(); } catch (Exception ex) { failure = ex; }
                BeginInvoke((Action)delegate {
                    SetBusy(false);
                    if (failure != null)
                    {
                        status.Text = "작업 보류 · " + failure.Message; Log.Failure(title,failure);
                        if (done != null && snapshot != null && title != "Windows 시작 항목과 실행 상태 검사 중…") RefreshScan();
                    }
                    else if (done != null) done();
                });
            });
            worker.IsBackground = true; worker.SetApartmentState(ApartmentState.STA); worker.Start();
        }
        void RefreshScan()
        {
            Snapshot next = null; var roots = extra.ToArray();
            snapshot = null; Buttons();
            Work("Windows 시작 항목과 실행 상태 검사 중…",delegate { next = Snapshot.Scan(roots,disk,elevated); },
                delegate { snapshot = next; Render(); });
        }
        void Buttons()
        {
            bool ok = snapshot != null && snapshot.JournalError == "";
            bool pending = ok && snapshot.Journal != null && snapshot.Journal.Pending != "";
            apply.Enabled = ok && !pending && snapshot.Entries.Any(e=>e.Eligible);
            restore.Enabled = ok && !pending && (!elevated || (snapshot.Journal != null && snapshot.Journal.Owned.Count > 0));
            undo.Visible = pending;
            showLegacy.Visible = snapshot != null && snapshot.LegacyVisibleCandidate;
        }
        void Render()
        {
            var s = snapshot; var j = s.Journal;
            entries.BeginUpdate(); entries.Items.Clear();
            foreach (var e in s.Entries.OrderByDescending(i=>i.Eligible).ThenBy(i=>i.Label))
            {
                var row = new ListViewItem(new[]{ e.Eligible ? "변경 예정" : "조회",e.Label,e.Change ?? "",e.Proof ?? "" });
                row.Tag = e; row.ToolTipText = e.Details ?? e.Proof; entries.Items.Add(row);
            }
            if (s.Entries.Count == 0)
                entries.Items.Add(new ListViewItem(new[] { "조회 결과", "변경 가능한 항목 0건", "실행 상태 · 확인 필요 탭 확인", "" }));
            entries.EndUpdate();
            status.Text = "검사 완료   ·   변경 가능 " + s.Entries.Count(e=>e.Eligible) + "건   ·   실행 관찰 " +
                s.Processes.Count + "건   ·   확인 사항 " + s.Notes.Count + "건" + ((j != null && j.Pending != "") ? "   ·   복구 필요" : "");
            Log.Message(status.Text);
            runtime.Lines = new[]{"현재 실행 관찰"}.Concat(s.Processes.DefaultIfEmpty("검사 범위에서 발견되지 않았습니다."))
                .Concat(new[]{"","확인 사항"}).Concat(s.Notes.Distinct().DefaultIfEmpty("추가 확인 사항 없음"))
                .Concat(new[]{"","검사에 사용한 GMS 경로"}).Concat(s.Roots.DefaultIfEmpty("확인된 설치 경로 없음")).ToArray();
            var lines = new List<string>();
            if (j == null) lines.Add(s.JournalError == "" ? "복구 기록을 확인하려면 관리자 권한으로 열어 주세요." : s.JournalError);
            else
            {
                lines.Add("보관된 복원 대상  " + j.Owned.Count + "건");
                if (j.Pending != "") lines.Add("작업 중단 기록  " + j.Pending + " · '중단된 작업 복구'를 선택하세요.");
                if (j.Owned.Count > 0)
                    lines.Add(j.Boot == "" || s.Boot == "" ? "부팅 시각 미확인" : j.Boot == s.Boot ?
                        "마지막 적용과 같은 부팅 세션" : "마지막 적용 후 새 부팅 세션 관찰 · 시작 항목과 실행 관찰을 함께 확인하세요.");
                lines.AddRange(s.Saved);
            }
            lines.Add(""); lines.Add("백업 위치  " + disk.Folder); lines.Add("진단 로그  " + Log.Location);
            recovery.Lines = lines.ToArray(); Buttons();
            if (initialReview != "")
            {
                string request = initialReview;
                initialReview = "";
                OpenRequestedReview(request);
            }
        }
        void OpenRequestedReview(string request)
        {
            bool manual = request == "--review-manual";
            string title = manual ? "수동 전환 미리보기" : "기존 설정 복원 확인";
            if (!elevated)
            {
                string message = manual
                    ? "현재 계정에서 확인한 변경 후보\r\n\r\n" + String.Join("\r\n",
                        snapshot.Entries.Where(e=>e.Eligible).Select(e=>"• " + e.Label + "   " + e.Change).DefaultIfEmpty("확인된 후보 없음"))
                    : "원래 백업과 현재 상태를 대조하려면 같은 Windows 계정의 관리자 권한이 필요합니다.";
                if (Review(title,message + "\r\n\r\n관리자 창에서 다시 검사한 뒤 최종 변경 목록을 확인합니다.",true,
                    "관리자 권한으로 검토") && Program.Elevate(request)) Close();
                return;
            }
            if (manual ? apply.Enabled : restore.Enabled) { Change(manual); return; }
            string detail = snapshot.JournalError != "" ? snapshot.JournalError :
                snapshot.Journal != null && snapshot.Journal.Pending != "" ? "먼저 '중단된 작업 복구'에서 이전 작업을 확인하세요." :
                manual ? "현재 검사 범위에서 전환할 시작 항목을 찾지 못했습니다." : "이 계정에 보관된 복원 대상이 없습니다.";
            Review(title,detail,false);
        }
        bool Review(string title,string body,bool confirm,string confirmLabel = null)
        {
            using (var dialog = new Form { Text = title, StartPosition = FormStartPosition.CenterParent,
                Size = new Size(720,480), MinimumSize = new Size(460,320), Font = Font, ShowInTaskbar = false })
            {
                var panel = TextPanel(); panel.Text = body; panel.Font = new Font(Font.FontFamily,10);
                var footer = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 48, FlowDirection = FlowDirection.RightToLeft };
                var cancel = new Button { Text = confirm ? "취소" : "닫기", DialogResult = DialogResult.Cancel, AutoSize = true };
                footer.Controls.Add(cancel); dialog.CancelButton = cancel;
                if (confirm) footer.Controls.Add(new Button { Text = confirmLabel ?? title, DialogResult = DialogResult.OK, AutoSize = true });
                dialog.Controls.Add(panel); dialog.Controls.Add(footer); dialog.Padding = new Padding(14);
                return dialog.ShowDialog(this) == DialogResult.OK;
            }
        }
        static IDisposable LegacyLock()
        {
            string path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),"GMS-OperatingMode","mode-state.json");
            var mutex = new Mutex(false,@"Global\GMS-OperatingMode-v1");
            try
            {
                bool acquired;
                try { acquired = mutex.WaitOne(0); } catch (AbandonedMutexException) { acquired = true; }
                if (!acquired) throw new IOException("v2가 실행 중입니다. 기존 창을 정상 종료한 후 다시 시도하세요. 숨은 창은 Windows 로그아웃 후에도 확인하세요.");
                try
                {
                    try { File.GetAttributes(path); throw new IOException("v2 복구 기록이 있습니다. v2의 원래 모드를 먼저 복구한 후 다시 검사하세요. 기존 기록을 보존해 주세요."); }
                    catch (FileNotFoundException) { } catch (DirectoryNotFoundException) { }
                    return new MutexLease(mutex);
                }
                catch { mutex.ReleaseMutex(); throw; }
            }
            catch { mutex.Dispose(); throw; }
        }
        sealed class MutexLease : IDisposable
        {
            readonly Mutex value; internal MutexLease(Mutex mutex) { value = mutex; }
            public void Dispose() { value.ReleaseMutex(); value.Dispose(); }
        }
        void Change(bool applying)
        {
            if (!Ready()) return;
            var s = snapshot; string title = applying ? "수동 모드 전환" : "기존 모드 복원";
            var list = applying ? s.Entries.Where(e=>e.Eligible).ToList() : s.Journal.Owned;
            string summary = applying ? "아래 시작 설정을 백업한 뒤 변경합니다. 실행 중인 서버는 별도로 정상 종료하세요." :
                "아래 항목을 백업 시점의 상태로 복원합니다. Windows가 놓친 일정 또는 시작 조건을 즉시 실행할 수 있습니다.";
            if (!Review(title,summary + "\r\n\r\n" + String.Join("\r\n",list.Select(e=>"• " + e.Label + "   " +
                (applying ? e.Change : "백업값 복원") + "\r\n    " + e.Proof)) +
                "\r\n\r\n확인 사항\r\n" + String.Join("\r\n",s.Notes),true)) return;
            int count = 0;
            Work(title,delegate {
                using (LegacyLock()) using (disk.Lock())
                {
                    var j = disk.Load(); var adapter = new WindowsEntries(s.Roots);
                    if (!applying && (s.Journal.Owned.Count != j.Owned.Count ||
                        !s.Journal.Owned.Select(e=>e.Key()).SequenceEqual(j.Owned.Select(e=>e.Key()))))
                        throw new IOException("백업 기록이 변경되었습니다. 다시 검사하세요.");
                    count = new Engine(disk,adapter.Read,adapter.Write).Run(j,s.Entries,s.Roots,applying,s.Boot);
                }
            },delegate { Log.Message(title + " " + count + "건"); MessageBox.Show(this,title + " · 설정 " + count +
                "건 처리. 다시 검사합니다.",Text); RefreshScan(); });
        }
        void Recover()
        {
            if (!Ready()) return;
            if (!Review("중단된 작업 복구","마지막 전환 시도 직전 상태로 되돌립니다. 외부 변경이 발견되면 해당 지점에서 멈춥니다.\r\n\r\n" +
                String.Join("\r\n",snapshot.Journal.Steps.Take(snapshot.Journal.Intent).Select(e=>e.Label)),true)) return;
            Work("중단된 작업 복구",delegate {
                using (LegacyLock()) using (disk.Lock())
                { var j = disk.Load(); var system = new WindowsEntries(j.Roots); new Engine(disk,system.Read,system.Write).Recover(j); }
            },RefreshScan);
        }
        void Start()
        {
            if (!Ready() || !Review("Host 수동 시작","GSC Host 서비스를 지금 시작합니다. Host 설정에 따라 서버, StatusAgent 및 Discord 전송도 시작될 수 있습니다.",true)) return;
            Work("Host 수동 시작",delegate { using (LegacyLock()) using (disk.Lock()) RuntimeOps.StartHost(snapshot.Roots); },RefreshScan);
        }
        void Shutdown()
        {
            if (!Ready() || !Review("Host 정상 종료","플레이어에게 알리고 접속 종료를 확인하세요. GSC 전체 종료 API가 서버 저장과 종료를 처리합니다. GSC 버전에 따라 Agent의 정상 종료가 실패하면 Host 내부에서 Agent 종료를 강제할 수 있습니다. 독립 Velocity와 별도 서버는 각각 원래 콘솔에서 정상 종료하세요.",true)) return;
            Work("GSC 정상 종료 진행 중…",delegate {
                using (LegacyLock()) using (disk.Lock()) RuntimeOps.Shutdown(snapshot.Roots,delegate(string step) {
                    Log.Message(step); BeginInvoke((Action)delegate { status.Text = step; });
                });
            },delegate { MessageBox.Show(this,"Host 종료 요청 처리 후 실행 상태를 다시 확인합니다. 독립 프록시와 미확인 프로세스도 확인하세요.",Text); RefreshScan(); });
        }
        void AddRoot()
        {
            if (!Ready()) return;
            using (var pick = new FolderBrowserDialog { Description = "해당 GMS 전용 서버 또는 Velocity 폴더를 선택하세요.", ShowNewFolderButton = false })
            {
                if (pick.ShowDialog(this) != DialogResult.OK) return;
                string dir = Path.GetFullPath(pick.SelectedPath);
                if (!File.Exists(Path.Combine(dir,"server.properties")) && !File.Exists(Path.Combine(dir,"velocity.toml")))
                    throw new IOException("server.properties 또는 velocity.toml이 있는 서버 전용 폴더를 선택하세요.");
                if (Review("검사 폴더 추가",dir + "\r\n\r\n이 폴더가 운영 중인 GMS 전용 서버인지 확인하세요. 다음 검사부터 시작 항목의 실행 경로와 대조합니다.",true))
                { extra.Add(dir); RefreshScan(); }
            }
        }
        void Guide()
        {
            Review("안전 종료 안내","1. 플레이어에게 알리고 접속 종료와 최근 월드 백업을 확인합니다.\r\n\r\n2. 수동 모드로 시작 설정을 전환한 뒤 Host 정상 종료를 사용합니다. 독립 실행 중인 서버는 원래 콘솔에서 stop을, Velocity는 shutdown을 실행하세요.\r\n\r\n3. GSC Client는 트레이에서 종료하고, 월드 저장 로그와 StatusAgent 종료를 확인하세요. Discord 상태판과 일일 요약은 Agent가 멈추면 중단됩니다.\r\n\r\n4. 재검사에서 남은 항목을 확인하세요. 승인된 시점에 재부팅 후 로그인해 다시 검사하고, 지연 시작과 일일 일정도 확인하세요.\r\n\r\n5. 서버를 쓸 때는 Host 수동 시작이나 기존 관리 도구를 사용하세요.",false);
        }
    }
}
