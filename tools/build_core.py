#!/usr/bin/env python3
"""Write core-dt2's mod.json and sharc_raw.json (Digitakt II OS 1.17; written for 2.0, used since).

    python3 build_core.py --stock Digitakt_II_OS1.17.syx --tool elektron-firmware-tool --digikit MODULES

MODULES is the patchkit modules folder of the All-in-One v0.3.0 release (its dsp-inline object and the 1.17
port's anchors). core 1.0's seven sites are kept as they are; the rest are DigiKit's core/machines,
core/params and core/dsp-inline sites with tables of a fixed size (machines.s, params.s), and the knob slot.
"""
import argparse, json, os, struct, subprocess, sys, tempfile, tomllib

B = 0x40000400
CORE10_DEFSYM = {"DRAWALL": "0x4011bc96", "KEYDISP": "0x40030bd0", "ENCDISP": "0x40030b64", "OP_NEW": "0x4011ebd0",
                 "ITEM_CTOR": "0x40115a44", "MENU_ADD": "0x4011527a", "FN_MGR": "0x4019d8a8",
                 "SETTINGS_RET": "0x400a5eb2", "NO_DTIM0": "1", "VBR_FN": "0x400019b0"}
CORE10_SITES = [
    {'addr': '0x40000538', 'stock': '4eb9400019b0', 'op': 'jsr', 'target': 'boot'},
    {'addr': '0x40032ad4', 'stock': '4eb94011bc60', 'op': 'jsr', 'target': 'core_tick'},
    {'addr': '0x40032b3a', 'stock': '4eb94011bc96', 'op': 'jsr', 'target': 'core_draw'},
    {'addr': '0x40033d94', 'stock': '4eb940030bd0', 'op': 'jsr', 'target': 'core_key'},
    {'addr': '0x40033dde', 'stock': '4eb940030b64', 'op': 'jsr', 'target': 'core_enc'},
    {'addr': '0x400a5eac', 'stock': '205248780002', 'op': 'jmp', 'target': 'core_settings'},
    {'addr': '0x4009e2a2', 'stock': '4cef7c7c0018', 'op': 'jmp', 'target': 'core_personalize'}]
MF_LAST, PF_N = 23, 64

# (anchor, length, routine): DigiKit's hooks; the routines end with the displaced instructions themselves
HOOKS = [('cf.machines.dispatch', 6, 'mf_dispatch'), ('cf.machines.pagecount', 8, 'mo_count'),
         ('cf.machines.setpage', 8, 'mo_setpage'), ('cf.machines.list_entry', 8, 'mf_list_entry'),
         ('cf.machines.rank', 6, 'mf_rank'), ('cf.machines.clone.0', 8, 'mf_clone0'),
         ('cf.machines.clone.1', 6, 'mf_clone1'), ('cf.machines.clone.2', 8, 'mf_clone2'),
         ('cf.machines.clone.3', 6, 'mf_clone3'), ('cf.machines.clone.4', 6, 'mf_clone4'),
         ('cf.machines.clone.5', 6, 'mf_clone5'), ('cf.machines.clone.6', 6, 'mf_clone6'),
         ('cf.machines.typearg.0', 8, 'mf_typearg'), ('cf.params.t2', 6, 'pf_t2'),
         ('cf.params.drawone', 8, 'pf_drawone'), ('cf.params.randone', 8, 'pf_randone')]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--stock', required=True)
    ap.add_argument('--tool', required=True)
    ap.add_argument('--digikit', required=True, help="the release's patchkit/modules folder")
    ap.add_argument('--out', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'core'))
    a = ap.parse_args()
    work = tempfile.mkdtemp()
    subprocess.run([a.tool, '-i', a.stock, '-o', work], check=True, capture_output=True)
    img = open(os.path.join(work, 'section_3_MAIN_OS.bin'), 'rb').read()
    at = lambda addr, n: img[addr - B:addr - B + n]
    u32 = lambda addr: struct.unpack('>I', at(addr, 4))[0]
    port = tomllib.load(open(os.path.join(a.digikit, '..', 'devices', 'ports', 'dt2-1.17.toml'), 'rb'))
    A = {x['name']: x for x in port['anchor']}
    adr = lambda n: A[n]['addr']

    sites = list(CORE10_SITES)

    def bytes_site(addr, new, relocs=None, kind='data'):
        s = {'addr': '0x%08x' % addr, 'stock': at(addr, len(new)).hex(), 'op': 'bytes', 'new': new.hex(), 'kind': kind}
        if relocs:
            s['relocs'] = relocs
        sites.append(s)

    def ptr(addr, sym, add=0):
        sites.append({'addr': '0x%08x' % addr, 'stock': at(addr, 4).hex(), 'op': 'ptr', 'target': sym, 'addend': add}
                     if add else {'addr': '0x%08x' % addr, 'stock': at(addr, 4).hex(), 'op': 'ptr', 'target': sym})

    hook_at = lambda anchor: adr(anchor) + (4 if anchor == 'cf.params.t2' else 0)   # DigiKit: t2 at offset 4
    for anchor, n, fn in HOOKS:
        sites.append({'addr': '0x%08x' % hook_at(anchor), 'stock': at(hook_at(anchor), n).hex(), 'op': 'jmp',
                      'target': fn})
    # the machine list: a fixed allocation (all 24 types), the begin from mf_list_buf, the end read from mf_list_end
    lst, alloc = adr('cf.machines.list'), adr('cf.machines.list_alloc')
    assert at(alloc, 4) == bytes.fromhex('4878001c') and at(lst, 6) == bytes.fromhex('4879401f5474')
    assert at(lst + 6, 4) == bytes.fromhex('41e8001c') and at(lst + 10, 2) == bytes.fromhex('4879')
    bytes_site(alloc + 2, struct.pack('>H', 4 * (MF_LAST + 1)))
    bytes_site(lst, bytes.fromhex('2f39') + bytes(4), [[2, 'abs32', 'sym:mf_list_end', 0]], 'code')
    bytes_site(lst + 8, struct.pack('>H', 4 * (MF_LAST + 1)))
    ptr(lst + 12, 'mf_list_buf')
    # bounds: the last type is 23
    grp = adr('cf.machines.group')
    assert at(grp, 6) == bytes.fromhex('7206b2806604')
    bytes_site(grp + 1, bytes([MF_LAST]))
    bytes_site(grp + 4, b'\x65')                     # bne -> bcs: every added type is in SLICE's group
    for i, off in enumerate((0x12, 0x14, 0x14)):
        nm = adr('cf.machines.name.%d' % i)
        assert at(nm, 2) == bytes.fromhex('7206')
        bytes_site(nm + 1, bytes([MF_LAST]))
        ptr(nm + off, 'mf_names', 4 * i)
    pm = adr('cf.machines.permit')
    assert at(pm + 2, 2) == bytes.fromhex('7406')
    bytes_site(pm + 3, bytes([MF_LAST]))
    ptr(pm + 0x1a, 'mf_permit')
    ps = adr('cf.machines.persist')
    assert at(ps, 2) == bytes.fromhex('7408')
    bytes_site(ps + 1, bytes([8 + MF_LAST - 6]))      # (u8)(type + 1) < 25 keeps types up to 23
    for i, off in enumerate((0x8, 0xc, 0xc, 0x10, 0x8, 0x22)):
        pt = adr('cf.machines.pertype.%d' % i)
        assert at(pt + 1, 1) == b'\x06', hex(pt)
        bytes_site(pt + 1, bytes([MF_LAST]))
        ptr(pt + off, 'mf_pertype')
    # parameters: every reference into the stock table points into pf_table, every clamp bound grows by 64
    t1 = adr('cf.params.t1')
    for x in port['anchor']:
        if x['name'].startswith('cf.params.ref.'):
            ptr(x['addr'], 'pf_table', u32(x['addr']) - t1)
    for x in port['anchor']:
        if x['name'].startswith('cf.params.bound.'):
            assert u32(x['addr'] + 2) in (274, 275), hex(x['addr'])        # cmpi.l / cmpa.l #N
            bytes_site(x['addr'] + 2, struct.pack('>I', u32(x['addr'] + 2) + PF_N))
    # the knob slot of SourcePageView (UI 2.1's place)
    assert at(0x401edd4c, 4) == bytes.fromhex('40069b8e')
    ptr(0x401edd4c, 'core_knob_widget')
    # the code-at-knob slot of SourcePageView (vfunc 47): page 2 of an added machine
    assert at(0x401edd54, 4) == bytes.fromhex('40017cd4')
    ptr(0x401edd54, 'mo_codeat')
    # the frame builder after its fourth per-track copy: values 69 and 70 of a page-2 machine
    assert at(0x4002ebdc, 8) == bytes.fromhex('4fef000c37470094')
    sites.append({'addr': '0x4002ebdc', 'stock': '4fef000c37470094', 'op': 'jmp', 'target': 'core_frame_hi'})
    # core 2.4: the two loops that split value 28 into 29/30 (bank, slot) and join them back, skipped for page-2 machines
    assert at(0x4002e8de, 8) == bytes.fromhex('4a80671c302c005a')
    sites.append({'addr': '0x4002e8de', 'stock': '4a80671c302c005a', 'op': 'jmp', 'target': 'core_split28'})
    assert at(0x4002e974, 8) == bytes.fromhex('4a80671c716c005a')
    sites.append({'addr': '0x4002e974', 'stock': '4a80671c716c005a', 'op': 'jmp', 'target': 'core_join28'})
    # core 2.1, storage.s: runtime 69/70 saved in storage slots 77/78 (the save and load tables, their users, bounds)
    ST_SAVE, ST_LOAD = 0x40213a50, 0x40213b64
    for lea in (0x400daeee, 0x400dbaee, 0x400dc81e, 0x400dc99e):
        assert u32(lea + 2) == ST_SAVE, hex(lea)
        ptr(lea + 2, 'st_save')
    for lea in (0x400daeb4, 0x400db426):
        assert u32(lea + 2) == ST_LOAD, hex(lea)
        ptr(lea + 2, 'st_load')
    for addr, old, new in ((0x400daea2, '744c', '744e'),      # slot -> runtime map: slot <= 76 -> <= 78
                           (0x400daedc, '7444', '7446'),      # runtime -> slot map: runtime <= 68 -> <= 70
                           (0x400dc680, '784c', '784e'),      # pattern-lock load: lock id <= 76 -> <= 78
                           (0x400db444, '0000009a', '0000009e'),   # sound load: 77 slots -> 79
                           (0x400dbb0c, '0000008a', '0000008e')):  # sound save: 69 values -> 71
        assert at(addr, len(old) // 2).hex() == old, hex(addr)
        bytes_site(addr, bytes.fromhex(new))
    # the SRC-group walk's end function (stock 0x400da004) in the list builder: on to 69, 70 for a page-2 machine
    assert at(0x40050b46, 6) == bytes.fromhex('47f9400da004')
    ptr(0x40050b48, 'st_list_end')
    sites.append({'addr': '0x4000053e', 'stock': '4ebaff1c4ebaff6e', 'op': 'jsr', 'target': 'core_boot_late'})
    sites.sort(key=lambda s: int(s['addr'], 16))

    defsym = dict(CORE10_DEFSYM)    # the tables are built at 0x4000053e (boot.s core_boot_late), not in .boot
    defsym.update({
        'MF_TAB_LIST': adr('cf.machines.tab.list'), 'MF_TAB_NAMES': adr('cf.machines.tab.names'),
        'MF_TAB_PERMIT': adr('cf.machines.tab.permit'), 'MF_TAB_PERTYPE': adr('cf.machines.tab.pertype'),
        'MF_DISPATCH': adr('cf.machines.dispatch'), 'MF_LIST_ENTRY': adr('cf.machines.list_entry'),
        'MF_RANK': adr('cf.machines.rank'), 'MF_RANK_FN': u32(adr('cf.machines.rank') + 2),
        'MF_TYPEARG': adr('cf.machines.typearg.0'), 'MF_TYPEARG_EXIT': adr('cf.machines.typearg.exit'),
        'MO_SRCVT': adr('cf.machines.sourcevt'), 'MO_CUR': adr('cf.machines.curtrack'),
        'MO_TRACK': adr('cf.machines.trackobj'), 'MO_TYPE': adr('cf.machines.tracktype'),
        'MO_COUNT': adr('cf.machines.pagecount'), 'MO_SETPAGE': adr('cf.machines.setpage'),
        'PF_T1': t1, 'PF_T2': adr('cf.params.t2') + 4, 'PF_DRAWONE': adr('cf.params.drawone'),
        'PF_RANDONE': adr('cf.params.randone'), 'PF_RAND': adr('cf.params.rand'), 'PF_WRITE': adr('cf.params.write'),
        'KNOB_STOCK': 0x40069b8e, 'ST_SAVE': 0x40213a50, 'ST_LOAD': 0x40213b64, 'MO_CODEAT': 0x40017cd4, 'FRAME_HI_RET': 0x4002ebe4,
        'FILLRECT': 0x401131ae, 'TEXTF': 0x40113d84, 'FONT5': 0x402a9be0})
    for i in (0, 1, 2, 3, 4, 5, 6):
        defsym['MF_C%d' % i] = adr('cf.machines.clone.%d' % i)
        if 'cf.machines.clone.%d.alt' % i in A:
            defsym['MF_C%dA' % i] = adr('cf.machines.clone.%d.alt' % i)
    assert u32(adr('cf.machines.rank') + 2) == 0x401aae3c
    assert at(adr('cf.params.t2') + 4, 6) == bytes.fromhex('0c8000000113')
    defsym = {k: (v if isinstance(v, str) else '0x%08x' % v) for k, v in defsym.items()}

    doc = {
        'id': 'core', 'version': '2.4', 'license': 'AGPL-3.0-or-later', 'title': 'core',
        'category': 'Framework', 'author': 'irpina (core 1.0), Em D (DigiKit frameworks); core 2.0 port',
        'description': 'The boot copier and the hook bus for the Digitakt II (core 1.0), and the frameworks '
                       'mods build on: added machine types (core_machines), added parameters (core_params), '
                       'knob drawers (core_knobs), and on the DSP the in-renderer voice hook (DigiKit\'s '
                       'core/machines, core/params and core/dsp-inline) with the tables mods add to. On its own '
                       'it changes nothing the unit does.',
        'device': 'digitakt-mk2', 'os': '1.17',
        'sources': ['core.s', 'settings.s', 'fast.s', 'personalize.s', 'boot.s', 'machines.s', 'params.s', 'knobs.s', 'storage.s'],
        'defsym': defsym,
        'subscribe': [{'event': 'ev_tick', 'fn': 'core_fastcopy', 'order': 0},
                      {'event': 'ev_draw', 'fn': 'mo_draw', 'order': 99}],
        'collections': {'ev_tick': 4, 'ev_draw': 4, 'ev_key': 4, 'ev_enc': 4, 'ev_settings': 4,
                        'ev_personalize': 4, 'core_fast': 16, 'core_machines': 4, 'core_params': 4,
                        'core_knobs': 12},
        'sharc_raw': 'sharc_raw.json',
        'sites': sites,
    }
    os.makedirs(a.out, exist_ok=True)
    json.dump(doc, open(os.path.join(a.out, 'mod.json'), 'w'), indent=1)

    # ---- the DSP: dsp-inline (relocatable), its hook's tail, the selector table, the voice table, two patches
    dsp = lambda n: A[n]['addr']
    pc16 = lambda addr: 0x1c0000 + (addr - 0x28380000) // 2      # the L1 code block (0x380000-0x3a0000)
    externs = {'_fw_records': dsp('dsp.inline.voice_records'), '_fw_type_cache': dsp('dsp.voice.type_cache'),
               '_fw_frame': dsp('dsp.inline.frame_base'), '_fw_trig_latch': dsp('dsp.inline.trig_latch'),
               '_fw_release_latch': dsp('dsp.inline.release_latch'),
               '_fw_decimate': pc16(dsp('dsp.inline.decimate')),
               '_fw_after_decimate': pc16(dsp('dsp.inline.after_decimate'))}
    assert externs['_fw_trig_latch'] == 0x24f0cc and externs['_fw_decimate'] == 0x1c524a
    dko = os.path.join(a.out, 'dsp-inline-dsp.dko.json')
    with open(os.path.join(a.digikit, 'core', 'dsp-inline', 'build', 'dsp-inline-dsp.dko.json')) as fh:
        open(dko, 'w').write(fh.read())
    sel = dsp('dsp.machines.selector_data')
    entry = dsp('dsp.voice.render_entry') + 0x8c
    raw = {
        'objects': [
            {'dko': 'dsp-inline-dsp.dko.json', 'name': 'dsp-inline',
             'externs': {k: '0x%x' % v for k, v in externs.items()},
             'rename': {'_di_table': 'core_dsp_voices', '_fw_stock': 'core_dsp_voice_tail'}},
            {'name': 'voice-hook-tail',
             'sections': [{'name': 'tail', 'kind': 'text', 'align': 8, 'hex': '5499a801408c' + '3e061c00184f'}],
             'symbols': [{'name': 'core_dsp_voice_tail', 'section': 'tail', 'value': 0, 'global': True}],
             'relocs': []}],
        'tables': {
            'core_dsp_voices': {'kind': 'list', 'row': 8, 'max': 16, 'end': '00' * 8},
            'core_mf_selector': {'kind': 'indexed', 'row': 4, 'rows': MF_LAST + 1,
                                 'default': [['stock', '0x%x' % sel, 4]]}},
        'contribute': [{'to': 'core_mf_selector', 'index': t, 'parts': [['stock', '0x%x' % (sel + 4 * t), 4]]}
                       for t in range(7)],
        'patches': [
            {'addr': '0x28384e64', 'stock': '2500', 'new': '0000', 'relocs': [[0, 'hi16', 'sym:core_mf_selector', 0]]},
            {'addr': '0x28384e66', 'stock': 'c067', 'new': '0000', 'relocs': [[0, 'lo16', 'sym:core_mf_selector', 0]]},
            {'addr': '0x%x' % entry, 'stock': '5499a801408c', 'new': '3e0600000000',
             'relocs': [[0, 'sharc.abs24', 'sym:_di_entry', 0]]}],
    }
    assert entry == 0x28389e2a
    json.dump(raw, open(os.path.join(a.out, 'sharc_raw.json'), 'w'), indent=1)
    print('core 2.0:', len(sites), 'sites')


if __name__ == '__main__':
    main()
