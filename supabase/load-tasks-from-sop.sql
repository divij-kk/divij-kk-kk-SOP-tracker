-- =====================================================================
-- KK Daily Tasks · load every task from the SOP - FACTORY sheet ("TASK LISTS" tab)
-- Paste into Supabase → SQL Editor → Run.  84 tasks, all set as DAILY tasks.
-- Safe to re-run: a task the manager already has (same wording, any capitals) is skipped.
-- This only ADDS tasks. To remove tasks later, use Import Excel in the admin login.
-- The result table shows, per manager, how many tasks were added.
-- =====================================================================
with sheet(manager, title, pos) as (values
  ('ANANDMOY BANERJEE', 'QC - PHYSICAL DAILY', 0),
  ('ANUP ROY', 'COVER MATERIAL ISSUE FOR MFG - PANELS, TIPS , STRAPS', 0),
  ('ANUP ROY', 'MIS SUBMISSION', 1),
  ('ANUP ROY', 'COVER MFG PLANNING', 2),
  ('ANUP ROY', 'TIPS MACHINE REPAIR', 3),
  ('ANUP ROY', 'STAPLE MACHINE REPAIR', 4),
  ('ANUP ROY', 'GODOWN REORGANISING - B23F', 5),
  ('ANUP ROY', 'STOCK UPDATE OF CHILD DEPARTMENTS', 6),
  ('ANUP ROY', 'PRINTING WORK - PLANNING', 7),
  ('ANUP ROY', 'PRINTING WORK - ISSUING', 8),
  ('ANUP ROY', 'PRINTING WORK - COLLECTION', 9),
  ('ANUP ROY', 'PRINTING WORK - STOCK SHEET', 10),
  ('ANUP ROY', 'QC - PHYSICAL DAILY', 11),
  ('AVINASH SHAW', 'KSPL INVOICING', 0),
  ('BACHU BAKULI', 'DG OIL CHECK', 0),
  ('BOLAI SANTRA', 'QC ROUNDS - DAILY SOME LEVEL OF REPORTING NEEDED', 0),
  ('BOLAI SANTRA', 'QC - PHYSICAL DAILY', 1),
  ('HIMANSHU KUMAR', 'BOM APPROVAL', 0),
  ('HIMANSHU KUMAR', 'MIS SUBMISSION', 1),
  ('HIMANSHU KUMAR', 'QC - PHYSICAL DAILY', 2),
  ('HIMANSHU KUMAR', 'QC DAILY FOLLOW-UPS', 3),
  ('ISHAN CHATERJEE', 'CUTTING PLANNING', 0),
  ('ISHAN CHATERJEE', 'ROLL ISSUE FOR MFG', 1),
  ('ISHAN CHATERJEE', 'DAILY MFG NOTING', 2),
  ('ISHAN CHATERJEE', 'GODOWN REORGANISE', 3),
  ('ISHAN CHATERJEE', 'ISSUE READY PANELS WITH STRAPS TO COVER GODOWN', 4),
  ('ISHAN CHATERJEE', 'STRAP PLANNING', 5),
  ('ISHAN CHATERJEE', 'TUBE PLANNING', 6),
  ('ISHAN CHATERJEE', 'STRAP MATERIAL ISSUE', 7),
  ('ISHAN CHATERJEE', 'TUBE MATERIAL ISSUE', 8),
  ('ISHAN CHATERJEE', 'SOH - PHYSICAL COPY UPDATE', 9),
  ('ISHAN CHATERJEE', 'REJECTION REPAIRING- PANELS', 10),
  ('ISHAN CHATERJEE', 'REJECTION REPAIRING- STRAPS', 11),
  ('ISHAN CHATERJEE', 'REJECTION REPAIRING- TUBES', 12),
  ('ISHAN CHATERJEE', 'MIS SUBMISSION', 13),
  ('ISHAN CHATERJEE', 'QC - PHYSICAL DAILY', 14),
  ('JOYDIP BAL', 'ANY PENDING INWARD FROM QUEEN LANDING AREA INTO GODOWN / BASIC GODOWN CLEANLINESS / FIX LOTS / TAKE PHYSICAL COUNTS TO MATCH SYSTEM DATA', 0),
  ('JOYDIP BAL', 'ENTER ALL MIR ISSUED DATA IN THE ERP', 1),
  ('JOYDIP BAL', 'ISSUE GOODS AGAINST M.I.R RECEIVED', 2),
  ('JOYDIP BAL', 'QC - PHYSICAL DAILY', 3),
  ('JOYESH GHOSH', 'MIS ENTRY', 0),
  ('JOYESH GHOSH', 'PLATING', 1),
  ('JOYESH GHOSH', 'QC - PHYSICAL DAILY', 2),
  ('JOYESH GHOSH', 'DEALER APP WORK', 3),
  ('LAKSHMIKANTA KARMAKAR', 'GODOWN WORK?', 0),
  ('LAKSHMIKANTA KARMAKAR', 'ISSUE STRAIGHT FRAMES', 1),
  ('LAKSHMIKANTA KARMAKAR', 'TAKAI COUNTING', 2),
  ('LAKSHMIKANTA KARMAKAR', 'QC - PHYSICAL DAILY', 3),
  ('MAINAK GANGULY', 'BASIC PACKING AREA CLEANLINESS', 0),
  ('MAINAK GANGULY', 'LOOSE STOCK UPDATE', 1),
  ('MAINAK GANGULY', 'WORK DONE MIS NOTING', 2),
  ('MAINAK GANGULY', 'QC - PHYSICAL DAILY', 3),
  ('MAINAK GANGULY', 'DEALER APP WORK', 4),
  ('MAINAK GANGULY', 'QC DAILY ENTRIES', 5),
  ('MAINAK GANGULY', 'PACK PLANNING REPORT', 6),
  ('MOLOY DHARA', 'PDF RELATED WORK', 0),
  ('MOLOY DHARA', 'PRINT FG STICKERS', 1),
  ('MOLOY DHARA', 'PRINT HANGTAGS', 2),
  ('MOLOY DHARA', 'PRINT IC STICKERS', 3),
  ('MOLOY DHARA', 'PRINT QC STICKERS', 4),
  ('MOLOY DHARA', 'CONTAINER STICKERS', 5),
  ('MOLOY DHARA', 'QC - PHYSICAL DAILY', 6),
  ('MOLOY DHARA', 'CREATIVES', 7),
  ('RAJU SANTRA', 'FOLDING FRAME - ISSUE WORK', 0),
  ('RAJU SANTRA', 'FOLDING FRAME -INWARD MFG', 1),
  ('RAJU SANTRA', 'REJECTION FRAME - REPAIRING', 2),
  ('RAJU SANTRA', 'MIS SUBMISSION', 3),
  ('RAJU SANTRA', 'QC - PHYSICAL DAILY', 4),
  ('SOUMITRO DE', 'QC REJECT REPORT - SKU WISE', 0),
  ('SOUMITRO DE', 'QC - PHYSICAL DAILY', 1),
  ('SUROJIT CHAKRABORTY', 'QC - PHYSICAL DAILY', 0),
  ('TRIDIB MANDAL', 'ANY PENDING INWARD FROM QUEEN LANDING AREA INTO GODOWN / BASIC GODOWN CLEANLINESS / FIX LOTS / TAKE PHYSICAL COUNTS TO MATCH SYSTEM DATA', 0),
  ('TRIDIB MANDAL', 'ENTER ALL MIR ISSUED DATA IN THE ERP', 1),
  ('TRIDIB MANDAL', 'ISSUE GOODS AGAINST M.I.R RECEIVED', 2),
  ('TRIDIB MANDAL', 'QC - PHYSICAL DAILY', 3),
  ('UMA CHINA', 'PLAN CLEANING TASKS FOR THE DAY', 0),
  ('UMA CHINA', 'PLAN DAILYMEN TASKS FOR THE DAY', 1),
  ('UMA CHINA', 'QC - PHYSICAL DAILY', 2),
  ('UMA CHINA', 'CLEAR - RICE AREA', 3),
  ('UMA CHINA', 'CLEAR - STAIRWAYS', 4),
  ('UMA CHINA', 'SCRAP - METAL - ORGANISE', 5),
  ('UMA CHINA', 'SCRAP - FABRIC - ORGANISE', 6),
  ('UMA CHINA', 'MRO - CUPBOARD MAINTENANCE', 7),
  ('UMA CHINA', 'SCRAP SALE', 8)
),
matched as (
  select s.*, p.id as manager_id
  from sheet s
  left join public.profiles p
    on p.role = 'manager' and upper(regexp_replace(trim(p.full_name), '\s+', ' ', 'g')) = s.manager
),
added as (
  insert into public.tasks (manager_id, title, task_type, priority, repeat_every, sort_order, start_date, active)
  select m.manager_id, m.title, 'daily', 'normal', 1, m.pos, public.ist_today(), true
  from matched m
  where m.manager_id is not null
    and not exists (
      select 1 from public.tasks t
      where t.manager_id = m.manager_id
        and lower(regexp_replace(trim(t.title), '\s+', ' ', 'g')) = lower(m.title))
  returning manager_id
)
select m.manager,
       case when (array_agg(m.manager_id))[1] is null then 'NAME NOT FOUND IN APP - nothing added' else 'ok' end as status,
       count(*) as tasks_in_sheet,
       (select count(*) from added a where a.manager_id = (array_agg(m.manager_id))[1]) as tasks_added_now
from matched m
group by m.manager
order by m.manager;
