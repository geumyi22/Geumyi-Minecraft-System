using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Xml;

namespace GmsMode
{
    public sealed partial class WindowsEntries
    {
        static dynamic Scheduler()
        {
            dynamic service=Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service",true));
            try { service.Connect(); return service; }
            catch { Release(service); throw; }
        }
        static void Release(object obj) { if (obj!=null && Marshal.IsComObject(obj)) Marshal.ReleaseComObject(obj); }
        static XmlDocument Xml(string s)
        {
            var x=new XmlDocument { XmlResolver=null };
            var opts=new XmlReaderSettings { DtdProcessing=DtdProcessing.Prohibit,XmlResolver=null,MaxCharactersInDocument=4*1024*1024 };
            using (var reader=XmlReader.Create(new StringReader(s),opts)) x.Load(reader);
            if (x.DocumentElement.LocalName!="Task" || x.DocumentElement.NamespaceURI!="http://schemas.microsoft.com/windows/2004/02/mit/task") throw Invalid();
            return x;
        }
        static XmlNode Child(XmlNode n,string name)
        {
            return n.ChildNodes.Cast<XmlNode>().FirstOrDefault(x=>x.LocalName==name && x.NamespaceURI==n.NamespaceURI);
        }
        static string Val(XmlNode n,string field)
        {
            var c=Child(n,field); return c==null?"":c.InnerText;
        }
        static XmlNode[] Children(XmlNode node)
        {
            return node==null ? new XmlNode[0] : node.ChildNodes.Cast<XmlNode>().Where(n=>n.NodeType==XmlNodeType.Element).ToArray();
        }
        internal string TaskProof(XmlDocument doc)
        {
            var actions=Children(Child(doc.DocumentElement,"Actions"));
            if (actions.Length==0) return null;
            var proofs=new List<string>();
            foreach (XmlNode a in actions)
            {
                if (a.LocalName!="Exec" || a.NamespaceURI!=doc.DocumentElement.NamespaceURI) return null;
                string target=Val(a,"Command").Trim();
                if (target.Length>=2 && target[0]=='"' && target[target.Length-1]=='"') target=target.Substring(1,target.Length-2);
                string proof=owner.Target(target,WindowsOwnership.Args("launcher "+Val(a,"Arguments")).Skip(1).ToArray(),Val(a,"WorkingDirectory"));
                if (proof==null) return null;
                if (!proofs.Contains(proof,CI)) proofs.Add(proof);
            }
            return String.Join(" + ",proofs);
        }
        // Keep the registered XML, including omitted defaults and security metadata.
        // ITaskDefinition.XmlText expands default settings even for an unchanged copy.
        internal static string DisabledTriggers(string before)
        {
            var doc=Xml(before);
            bool changed=false;
            foreach (var trigger in Children(Child(doc.DocumentElement,"Triggers")))
            {
                if (trigger.NamespaceURI!=doc.DocumentElement.NamespaceURI) throw Invalid();
                var enabled=Child(trigger,"Enabled");
                if (enabled!=null && !XmlConvert.ToBoolean(enabled.InnerText.Trim())) continue;
                if (enabled==null)
                {
                    enabled=doc.CreateElement(trigger.Prefix,"Enabled",trigger.NamespaceURI);
                    // Enabled is the first element of triggerBaseType in the task schema.
                    trigger.PrependChild(enabled);
                }
                enabled.InnerText="false";
                changed=true;
            }
            return changed ? doc.OuterXml : null;
        }
        // The service can move Enabled among a trigger's other fields on registration.
        // Normalize just this boolean; every other field, including order, must still match.
        static string TaskTriggerImage(string xml)
        {
            var doc=Xml(xml);
            foreach (var trigger in Children(Child(doc.DocumentElement,"Triggers")))
            {
                var flags=Children(trigger).Where(n=>n.NamespaceURI==trigger.NamespaceURI && n.LocalName=="Enabled").ToArray();
                if (flags.Length>1) throw Invalid();
                var flag=flags.FirstOrDefault();
                bool enabled=flag==null || XmlConvert.ToBoolean(flag.InnerText.Trim());
                if (flag==null) flag=doc.CreateElement(trigger.Prefix,"Enabled",trigger.NamespaceURI);
                else
                {
                    if (flag.Attributes.Count!=0 || Children(flag).Length!=0) throw Invalid();
                    trigger.RemoveChild(flag);
                }
                flag.InnerText=XmlConvert.ToString(enabled);
                trigger.PrependChild(flag);
            }
            return doc.OuterXml;
        }
        internal static string RecognizedTaskState(string live,string before,string after,string exactAfter)
        {
            if (live==before) return before;
            if (live==after || live==exactAfter) return after;
            string current=TaskTriggerImage(live);
            if (current==TaskTriggerImage(exactAfter)) return after;
            if (current==TaskTriggerImage(before)) return before;
            throw Invalid();
        }
        // Schema-3 journals from 3.0.0 contain the detached serializer's expanded XML.
        static string LegacyDisabledTriggers(dynamic service,string before)
        {
            dynamic def=null, triggers=null;
            try
            {
                def=service.NewTask(0); def.XmlText=before;
                triggers=def.Triggers; int count=(int)triggers.Count;
                bool changed=false;
                for (int i=1;i<=count;i++)
                {
                    dynamic t=triggers.Item(i);
                    try { if ((bool)t.Enabled) { t.Enabled=false; changed=true; } }
                    finally { Release(t); }
                }
                return changed ? Xml((string)def.XmlText).OuterXml : null;
            }
            finally { Release(triggers); Release(def); }
        }
        static int LogonType(dynamic task)
        {
            dynamic def=null, p=null;
            try { def=task.Definition; p=def.Principal; return (int)p.LogonType; }
            finally { Release(p); Release(def); }
        }
        static bool SupportedLogon(int n) { return n==2 || n==3 || n==4 || n==5; }
        void ScanTasks(List<Entry> rows,List<string> notes)
        {
            dynamic service=null,root=null;
            try { service=Scheduler(); root=service.GetFolder(@"\"); FolderRows(service,root,rows,notes); }
            catch (Exception ex) { Note(notes,"작업 스케줄러",ex); }
            finally { Release(root); Release(service); }
        }
        void FolderRows(dynamic service,dynamic folder,List<Entry> rows,List<string> notes)
        {
            string directory=(string)folder.Path;
            dynamic tasks=null,folders=null;
            try
            {
                tasks=folder.GetTasks(1); // Include hidden definitions.
                int count=(int)tasks.Count;
                for (int i=1;i<=count;i++)
                {
                    dynamic t=null;
                    string path=directory;
                    try
                    {
                        t=tasks.Item(i); path=(string)t.Path;
                        string raw=(string)t.Xml;
                        XmlDocument doc=Xml(raw);
                        string proof=TaskProof(doc);
                        if (proof==null)
                        {
                            XmlNode action=Child(doc.DocumentElement,"Actions");
                            if (WindowsOwnership.Hint(path+" "+(action==null?"":action.InnerText)) ||
                                Children(action).Any(x=>x.LocalName=="Exec" && WindowsOwnership.IndirectProgram(Val(x,"Command"))))
                                notes.Add("예약 작업 수동 확인 · "+path+" (복합 동작 또는 실행 대상 미확인)");
                            continue;
                        }
                        if (!(bool)t.Enabled) { notes.Add("이미 사용 안 함 · 예약 작업 "+path); continue; }
                        if (!SupportedLogon(LogonType(t))) { notes.Add("자격 증명 보존을 위해 수동 확인 · "+path); continue; }
                        string before=doc.OuterXml, after=DisabledTriggers(before);
                        if (after==null) { notes.Add("활성 트리거 없음 · "+path); continue; }
                        rows.Add(Item("Task",path,"예약 작업 · "+path,proof,before,after,"활성 트리거 해제 · 수동 실행 설정 보존"));
                    }
                    catch (Exception ex) { Note(notes,"예약 작업 "+path,ex); }
                    finally { Release(t); }
                }
            }
            catch (Exception ex) { Note(notes,"예약 작업 폴더 "+directory,ex); }
            finally { Release(tasks); }
            try
            {
                folders=folder.GetFolders(0);
                int count=(int)folders.Count;
                for (int i=1;i<=count;i++)
                {
                    dynamic sub=null;
                    try { sub=folders.Item(i); FolderRows(service,sub,rows,notes); }
                    catch (Exception ex) { Note(notes,"예약 작업 하위 "+directory,ex); }
                    finally { Release(sub); }
                }
            }
            catch (Exception ex) { Note(notes,"예약 작업 하위 "+directory,ex); }
            finally { Release(folders); }
        }
        string TaskAccess(Entry e,string next)
        {
            if (!e.Id.StartsWith(@"\") || e.Id.EndsWith(@"\") || e.Id.Split('\\').Any(s=>s==".." || s==".")) throw Invalid();
            string proof=TaskProof(Xml(e.Before));
            if (proof==null || !CI.Equals(proof,e.Proof)) throw Invalid();
            string exactAfter=DisabledTriggers(e.Before);
            if (exactAfter==null) throw Invalid();
            dynamic service=null,folder=null,t=null,definition=null,principal=null,registered=null;
            try
            {
                service=Scheduler();
                int at=e.Id.LastIndexOf('\\');
                folder=service.GetFolder(at==0?@"\":e.Id.Substring(0,at));
                t=folder.GetTask(e.Id.Substring(at+1));
                string now=Xml((string)t.Xml).OuterXml;
                if (exactAfter!=e.After && LegacyDisabledTriggers(service,e.Before)!=e.After) throw Invalid();
                now=RecognizedTaskState(now,e.Before,e.After,exactAfter);
                if (!CI.Equals((string)t.Path,e.Id) || !(bool)t.Enabled || !SupportedLogon(LogonType(t))) throw Invalid();
                if (next==null || next==now) return now;
                definition=t.Definition;
                principal=definition.Principal;
                int logon=(int)principal.LogonType;
                XmlNode principalXml=Children(Child(Xml(e.Before).DocumentElement,"Principals")).Single();
                string account=Val(principalXml,logon==4?"GroupId":"UserId");
                if (!SupportedLogon(logon) || String.IsNullOrEmpty(account)) throw Invalid();
                // TASK_UPDATE only; preserve DACL and suppress registration-trigger launches.
                // No password is read or needed for these accepted logon types.
                registered=folder.RegisterTask(e.Id.Substring(at+1),next==e.After?exactAfter:e.Before,4|16|32,account,null,logon,null);
                return next;
            }
            finally { Release(registered); Release(principal); Release(definition); Release(t); Release(folder); Release(service); }
        }
    }
}
