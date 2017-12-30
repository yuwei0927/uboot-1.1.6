01 /*
02  * Driver for NAND support, Rick Bronson
03  * borrowed heavily from:
04  * (c) 1999 Machine Vision Holdings, Inc.
05  * (c) 1999, 2000 David Woodhouse <dwmw2@infradead.org>
06  *
07  * Added 16-bit nand support
08  * (C) 2004 Texas Instruments
09  */
10 
11 #include <common.h>
12 
13 
14 #ifndef CFG_NAND_LEGACY
15 /*
16  *
17  * New NAND support
18  *
19  */
20 #include <common.h>
21 
22 #if (CONFIG_COMMANDS & CFG_CMD_NAND)
23 
24 #include <command.h>
25 #include <watchdog.h>
26 #include <malloc.h>
27 #include <asm/byteorder.h>
28 
29 #ifdef CONFIG_SHOW_BOOT_PROGRESS
30 # include <status_led.h>
31 # define SHOW_BOOT_PROGRESS(arg)    show_boot_progress(arg)
32 #else
33 # define SHOW_BOOT_PROGRESS(arg)
34 #endif
35 
36 #include <jffs2/jffs2.h>
37 #include <nand.h>
38 
39 #if (CONFIG_COMMANDS & CFG_CMD_JFFS2) && defined(CONFIG_JFFS2_CMDLINE)
40 
41 /* parition handling routines */
42 int mtdparts_init(void);
43 int id_parse(const char *id, const char **ret_id, u8 *dev_type, u8 *dev_num);
44 int find_dev_and_part(const char *id, struct mtd_device **dev,
45         u8 *part_num, struct part_info **part);
46 #endif
47 
48 extern nand_info_t nand_info[];       /* info for NAND chips */
49 
50 static int nand_dump_oob(nand_info_t *nand, ulong off)
51 {
52     return 0;
53 }
54 
55 static int nand_dump(nand_info_t *nand, ulong off)
56 {
57     int i;
58     u_char *buf, *p;
59 
60     buf = malloc(nand->oobblock + nand->oobsize);
61     if (!buf) {
62         puts("No memory for page buffer\n");
63         return 1;
64     }
65     off &= ~(nand->oobblock - 1);
66     i = nand_read_raw(nand, buf, off, nand->oobblock, nand->oobsize);
67     if (i < 0) {
68         printf("Error (%d) reading page %08x\n", i, off);
69         free(buf);
70         return 1;
71     }
72     printf("Page %08x dump:\n", off);
73     i = nand->oobblock >> 4; p = buf;
74     while (i--) {
75         printf( "\t%02x %02x %02x %02x %02x %02x %02x %02x"
76             "  %02x %02x %02x %02x %02x %02x %02x %02x\n",
77             p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7],
78             p[8], p[9], p[10], p[11], p[12], p[13], p[14], p[15]);
79         p += 16;
80     }
81     puts("OOB:\n");
82     i = nand->oobsize >> 3;
83     while (i--) {
84         printf( "\t%02x %02x %02x %02x %02x %02x %02x %02x\n",
85             p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7]);
86         p += 8;
87     }
88     free(buf);
89 
90     return 0;
91 }
92 
93 /* ------------------------------------------------------------------------- */
94 
95 static inline int str2long(char *p, ulong *num)
96 {
97     char *endptr;
98 
99     *num = simple_strtoul(p, &endptr, 16);
100     return (*p != '\0' && *endptr == '\0') ? 1 : 0;
101 }
102 
103 static int
104 arg_off_size(int argc, char *argv[], nand_info_t *nand, ulong *off, ulong *size)
105 {
106     int idx = nand_curr_device;
107 #if (CONFIG_COMMANDS & CFG_CMD_JFFS2) && defined(CONFIG_JFFS2_CMDLINE)
108     struct mtd_device *dev;
109     struct part_info *part;
110     u8 pnum;
111 
112     if (argc >= 1 && !(str2long(argv[0], off))) {
113         if ((mtdparts_init() == 0) &&
114             (find_dev_and_part(argv[0], &dev, &pnum, &part) == 0)) {
115             if (dev->id->type != MTD_DEV_TYPE_NAND) {
116                 puts("not a NAND device\n");
117                 return -1;
118             }
119             *off = part->offset;
120             if (argc >= 2) {
121                 if (!(str2long(argv[1], size))) {
122                     printf("'%s' is not a number\n", argv[1]);
123                     return -1;
124                 }
125                 if (*size > part->size)
126                     *size = part->size;
127             } else {
128                 *size = part->size;
129             }
130             idx = dev->id->num;
131             *nand = nand_info[idx];
132             goto out;
133         }
134     }
135 #endif
136 
137     if (argc >= 1) {
138         if (!(str2long(argv[0], off))) {
139             printf("'%s' is not a number\n", argv[0]);
140             return -1;
141         }
142     } else {
143         *off = 0;
144     }
145 
146     if (argc >= 2) {
147         if (!(str2long(argv[1], size))) {
148             printf("'%s' is not a number\n", argv[1]);
149             return -1;
150         }
151     } else {
152         *size = nand->size - *off;
153     }
154 
155 #if (CONFIG_COMMANDS & CFG_CMD_JFFS2) && defined(CONFIG_JFFS2_CMDLINE)
156 out:
157 #endif
158     printf("device %d ", idx);
159     if (*size == nand->size)
160         puts("whole chip\n");
161     else
162         printf("offset 0x%x, size 0x%x\n", *off, *size);
163     return 0;
164 }
165 
166 int do_nand(cmd_tbl_t * cmdtp, int flag, int argc, char *argv[])
167 {
168     int i, dev, ret;
169     ulong addr, off, size;
170     char *cmd, *s;
171     nand_info_t *nand;
172     int quiet = 0;
173     const char *quiet_str = getenv("quiet");
174 
175     /* at least two arguments please */
176     if (argc < 2)
177         goto usage;
178 
179     if (quiet_str)
180         quiet = simple_strtoul(quiet_str, NULL, 0) != 0;
181 
182     cmd = argv[1];
183 
184     if (strcmp(cmd, "info") == 0) {
185 
186         putc('\n');
187         for (i = 0; i < CFG_MAX_NAND_DEVICE; i++) {
188             if (nand_info[i].name)
189                 printf("Device %d: %s, sector size %lu KiB\n",
190                     i, nand_info[i].name,
191                     nand_info[i].erasesize >> 10);
192         }
193         return 0;
194     }
195 
196     if (strcmp(cmd, "device") == 0) {
197 
198         if (argc < 3) {
199             if ((nand_curr_device < 0) ||
200                 (nand_curr_device >= CFG_MAX_NAND_DEVICE))
201                 puts("\nno devices available\n");
202             else
203                 printf("\nDevice %d: %s\n", nand_curr_device,
204                     nand_info[nand_curr_device].name);
205             return 0;
206         }
207         dev = (int)simple_strtoul(argv[2], NULL, 10);
208         if (dev < 0 || dev >= CFG_MAX_NAND_DEVICE || !nand_info[dev].name) {
209             puts("No such device\n");
210             return 1;
211         }
212         printf("Device %d: %s", dev, nand_info[dev].name);
213         puts("... is now current device\n");
214         nand_curr_device = dev;
215 
216 #ifdef CFG_NAND_SELECT_DEVICE
217         /*
218          * Select the chip in the board/cpu specific driver
219          */
220         board_nand_select_device(nand_info[dev].priv, dev);
221 #endif
222 
223         return 0;
224     }
225 
226     if (strcmp(cmd, "bad") != 0 && strcmp(cmd, "erase") != 0 &&
227         strncmp(cmd, "dump", 4) != 0 &&
228         strncmp(cmd, "read", 4) != 0 && strncmp(cmd, "write", 5) != 0 &&
229         strcmp(cmd, "scrub") != 0 && strcmp(cmd, "markbad") != 0 &&
230         strcmp(cmd, "biterr") != 0 &&
231         strcmp(cmd, "lock") != 0 && strcmp(cmd, "unlock") != 0 )
232         goto usage;
233 
234     /* the following commands operate on the current device */
235     if (nand_curr_device < 0 || nand_curr_device >= CFG_MAX_NAND_DEVICE ||
236         !nand_info[nand_curr_device].name) {
237         puts("\nno devices available\n");
238         return 1;
239     }
240     nand = &nand_info[nand_curr_device];
241 
242     if (strcmp(cmd, "bad") == 0) {
243         printf("\nDevice %d bad blocks:\n", nand_curr_device);
244         for (off = 0; off < nand->size; off += nand->erasesize)
245             if (nand_block_isbad(nand, off))
246                 printf("  %08x\n", off);
247         return 0;
248     }
249 
250     /*
251      * Syntax is:
252      *   0    1     2       3    4
253      *   nand erase [clean] [off size]
254      */
255     if (strcmp(cmd, "erase") == 0 || strcmp(cmd, "scrub") == 0) {
256         nand_erase_options_t opts;
257         /* "clean" at index 2 means request to write cleanmarker */
258         int clean = argc > 2 && !strcmp("clean", argv[2]);
259         int o = clean ? 3 : 2;
260         int scrub = !strcmp(cmd, "scrub");
261 
262         printf("\nNAND %s: ", scrub ? "scrub" : "erase");
263         /* skip first two or three arguments, look for offset and size */
264         if (arg_off_size(argc - o, argv + o, nand, &off, &size) != 0)
265             return 1;
266 
267         memset(&opts, 0, sizeof(opts));
268         opts.offset = off;
269         opts.length = size;
270         opts.jffs2  = clean;
271         opts.quiet  = quiet;
272 
273         if (scrub) {
274             puts("Warning: "
275                  "scrub option will erase all factory set "
276                  "bad blocks!\n"
277                  "         "
278                  "There is no reliable way to recover them.\n"
279                  "         "
280                  "Use this command only for testing purposes "
281                  "if you\n"
282                  "         "
283                  "are sure of what you are doing!\n"
284                  "\nReally scrub this NAND flash? <y/N>\n");
285 
286             if (getc() == 'y' && getc() == '\r') {
287                 opts.scrub = 1;
288             } else {
289                 puts("scrub aborted\n");
290                 return -1;
291             }
292         }
293         ret = nand_erase_opts(nand, &opts);
294         printf("%s\n", ret ? "ERROR" : "OK");
295 
296         return ret == 0 ? 0 : 1;
297     }
298 
299     if (strncmp(cmd, "dump", 4) == 0) {
300         if (argc < 3)
301             goto usage;
302 
303         s = strchr(cmd, '.');
304         off = (int)simple_strtoul(argv[2], NULL, 16);
305 
306         if (s != NULL && strcmp(s, ".oob") == 0)
307             ret = nand_dump_oob(nand, off);
308         else
309             ret = nand_dump(nand, off);
310 
311         return ret == 0 ? 1 : 0;
312 
313     }
314 
315     /* read write */
316     if (strncmp(cmd, "read", 4) == 0 || strncmp(cmd, "write", 5) == 0) {
317         int read;
318 
319         if (argc < 4)
320             goto usage;
321 
322         addr = (ulong)simple_strtoul(argv[2], NULL, 16);
323 
324         read = strncmp(cmd, "read", 4) == 0; /* 1 = read, 0 = write */
325         printf("\nNAND %s: ", read ? "read" : "write");
326         if (arg_off_size(argc - 3, argv + 3, nand, &off, &size) != 0)
327             return 1;
328 
329         s = strchr(cmd, '.');
330         if (s != NULL &&
331             (!strcmp(s, ".jffs2") || !strcmp(s, ".e") || !strcmp(s, ".i"))) {
332             if (read) {
333                 /* read */
334                 nand_read_options_t opts;
335                 memset(&opts, 0, sizeof(opts));
336                 opts.buffer = (u_char*) addr;
337                 opts.length = size;
338                 opts.offset = off;
339                 opts.quiet      = quiet;
340                 ret = nand_read_opts(nand, &opts);
341             } else {
342                 /* write */
343                 nand_write_options_t opts;
344                 memset(&opts, 0, sizeof(opts));
345                 opts.buffer = (u_char*) addr;
346                 opts.length = size;
347                 opts.offset = off;
348                 /* opts.forcejffs2 = 1; */
349                 opts.pad    = 1;
350                 opts.blockalign = 1;
351                 opts.quiet      = quiet;
352                 ret = nand_write_opts(nand, &opts);
353             }
354         }else if (  s != NULL && !strcmp(s, ".yaffs")){
355             if (read) {
356                 /* read */
357                 nand_read_options_t opts;
358                 memset(&opts, 0, sizeof(opts));
359                 opts.buffer = (u_char*) addr;
360                 opts.length = size;
361                 opts.offset = off;
362                 opts.readoob = 1;
363                 opts.quiet      = quiet;
364                 ret = nand_read_opts(nand, &opts);
365             } else {
366                 /* write */
367                 nand_write_options_t opts;
368                 memset(&opts, 0, sizeof(opts));
369                 opts.buffer = (u_char*) addr;
370                 opts.length = size;
371                 opts.offset = off;
372                 /* opts.forceyaffs = 1; */
373                 opts.noecc = 1;
374                 opts.writeoob = 1;
375                 opts.blockalign = 1;
376                 opts.quiet      = quiet;
377                 opts.skipfirstblk = 1;
378                 ret = nand_write_opts(nand, &opts);
379             }
380         } else {
381             if (read)
382                 ret = nand_read(nand, off, &size, (u_char *)addr);
383             else
384                 ret = nand_write(nand, off, &size, (u_char *)addr);
385         }
386 
387         printf(" %d bytes %s: %s\n", size,
388                read ? "read" : "written", ret ? "ERROR" : "OK");
389 
390         return ret == 0 ? 0 : 1;
391     }
392 
393     if (strcmp(cmd, "markbad") == 0) {
394         addr = (ulong)simple_strtoul(argv[2], NULL, 16);
395 
396         int ret = nand->block_markbad(nand, addr);
397         if (ret == 0) {
398             printf("block 0x%08lx successfully marked as bad\n",
399                    (ulong) addr);
400             return 0;
401         } else {
402             printf("block 0x%08lx NOT marked as bad! ERROR %d\n",
403                    (ulong) addr, ret);
404         }
405         return 1;
406     }
407     if (strcmp(cmd, "biterr") == 0) {
408         /* todo */
409         return 1;
410     }
411 
412     if (strcmp(cmd, "lock") == 0) {
413         int tight  = 0;
414         int status = 0;
415         if (argc == 3) {
416             if (!strcmp("tight", argv[2]))
417                 tight = 1;
418             if (!strcmp("status", argv[2]))
419                 status = 1;
420         }
421 
422         if (status) {
423             ulong block_start = 0;
424             ulong off;
425             int last_status = -1;
426 
427             struct nand_chip *nand_chip = nand->priv;
428             /* check the WP bit */
429             nand_chip->cmdfunc (nand, NAND_CMD_STATUS, -1, -1);
430             printf("device is %swrite protected\n",
431                    (nand_chip->read_byte(nand) & 0x80 ?
432                 "NOT " : "" ) );
433 
434             for (off = 0; off < nand->size; off += nand->oobblock) {
435                 int s = nand_get_lock_status(nand, off);
436 
437                 /* print message only if status has changed
438                  * or at end of chip
439                  */
440                 if (off == nand->size - nand->oobblock
441                     || (s != last_status && off != 0))  {
442 
443                     printf("%08x - %08x: %8d pages %s%s%s\n",
444                            block_start,
445                            off-1,
446                            (off-block_start)/nand->oobblock,
447                            ((last_status & NAND_LOCK_STATUS_TIGHT) ? "TIGHT " : ""),
448                            ((last_status & NAND_LOCK_STATUS_LOCK) ? "LOCK " : ""),
449                            ((last_status & NAND_LOCK_STATUS_UNLOCK) ? "UNLOCK " : ""));
450                 }
451 
452                 last_status = s;
453                }
454         } else {
455             if (!nand_lock(nand, tight)) {
456                 puts("NAND flash successfully locked\n");
457             } else {
458                 puts("Error locking NAND flash\n");
459                 return 1;
460             }
461         }
462         return 0;
463     }
464 
465     if (strcmp(cmd, "unlock") == 0) {
466         if (arg_off_size(argc - 2, argv + 2, nand, &off, &size) < 0)
467             return 1;
468 
469         if (!nand_unlock(nand, off, size)) {
470             puts("NAND flash successfully unlocked\n");
471         } else {
472             puts("Error unlocking NAND flash, "
473                  "write and erase will probably fail\n");
474             return 1;
475         }
476         return 0;
477     }
478 
479 usage:
480     printf("Usage:\n%s\n", cmdtp->usage);
481     return 1;
482 }
483 
484 U_BOOT_CMD(nand, 5, 1, do_nand,
485     "nand    - NAND sub-system\n",
486     "info                  - show available NAND devices\n"
487     "nand device [dev]     - show or set current device\n"
488     "nand read[.jffs2]     - addr off|partition size\n"
489     "nand write[.jffs2]    - addr off|partiton size - read/write `size' bytes starting\n"
490     "    at offset `off' to/from memory address `addr'\n"
491     "nand read.yaffs addr off size - read the `size' byte yaffs image starting\n"
492     "    at offset `off' to memory address `addr'\n"
493     "nand write.yaffs addr off size - write the `size' byte yaffs image starting\n"
494     "    at offset `off' from memory address `addr'\n"
495     "nand erase [clean] [off size] - erase `size' bytes from\n"
496     "    offset `off' (entire device if not specified)\n"
497     "nand bad - show bad blocks\n"
498     "nand dump[.oob] off - dump page\n"
499     "nand scrub - really clean NAND erasing bad blocks (UNSAFE)\n"
500     "nand markbad off - mark bad block at offset (UNSAFE)\n"
501     "nand biterr off - make a bit error at offset (UNSAFE)\n"
502     "nand lock [tight] [status] - bring nand to lock state or display locked pages\n"
503     "nand unlock [offset] [size] - unlock section\n");
504 
505 static int nand_load_image(cmd_tbl_t *cmdtp, nand_info_t *nand,
506                ulong offset, ulong addr, char *cmd)
507 {
508     int r;
509     char *ep;
510     ulong cnt;
511     image_header_t *hdr;
512 
513     printf("\nLoading from %s, offset 0x%lx\n", nand->name, offset);
514 
515     cnt = nand->oobblock;
516     r = nand_read(nand, offset, &cnt, (u_char *) addr);
517     if (r) {
518         puts("** Read error\n");
519         SHOW_BOOT_PROGRESS(-1);
520         return 1;
521     }
522 
523     hdr = (image_header_t *) addr;
524 
525     if (ntohl(hdr->ih_magic) != IH_MAGIC) {
526         printf("\n** Bad Magic Number 0x%x **\n", hdr->ih_magic);
527         SHOW_BOOT_PROGRESS(-1);
528         return 1;
529     }
530 
531     print_image_hdr(hdr);
532 
533     cnt = (ntohl(hdr->ih_size) + sizeof (image_header_t));
534 
535     r = nand_read(nand, offset, &cnt, (u_char *) addr);
536     if (r) {
537         puts("** Read error\n");
538         SHOW_BOOT_PROGRESS(-1);
539         return 1;
540     }
541 
542     /* Loading ok, update default load address */
543 
544     load_addr = addr;
545 
546     /* Check if we should attempt an auto-start */
547     if (((ep = getenv("autostart")) != NULL) && (strcmp(ep, "yes") == 0)) {
548         char *local_args[2];
549         extern int do_bootm(cmd_tbl_t *, int, int, char *[]);
550 
551         local_args[0] = cmd;
552         local_args[1] = NULL;
553 
554         printf("Automatic boot of image at addr 0x%08lx ...\n", addr);
555 
556         do_bootm(cmdtp, 0, 1, local_args);
557         return 1;
558     }
559     return 0;
560 }
561 
562 int do_nandboot(cmd_tbl_t * cmdtp, int flag, int argc, char *argv[])
563 {
564     char *boot_device = NULL;
565     int idx;
566     ulong addr, offset = 0;
567 #if (CONFIG_COMMANDS & CFG_CMD_JFFS2) && defined(CONFIG_JFFS2_CMDLINE)
568     struct mtd_device *dev;
569     struct part_info *part;
570     u8 pnum;
571 
572     if (argc >= 2) {
573         char *p = (argc == 2) ? argv[1] : argv[2];
574         if (!(str2long(p, &addr)) && (mtdparts_init() == 0) &&
575             (find_dev_and_part(p, &dev, &pnum, &part) == 0)) {
576             if (dev->id->type != MTD_DEV_TYPE_NAND) {
577                 puts("Not a NAND device\n");
578                 return 1;
579             }
580             if (argc > 3)
581                 goto usage;
582             if (argc == 3)
583                 addr = simple_strtoul(argv[2], NULL, 16);
584             else
585                 addr = CFG_LOAD_ADDR;
586             return nand_load_image(cmdtp, &nand_info[dev->id->num],
587                            part->offset, addr, argv[0]);
588         }
589     }
590 #endif
591 
592     switch (argc) {
593     case 1:
594         addr = CFG_LOAD_ADDR;
595         boot_device = getenv("bootdevice");
596         break;
597     case 2:
598         addr = simple_strtoul(argv[1], NULL, 16);
599         boot_device = getenv("bootdevice");
600         break;
601     case 3:
602         addr = simple_strtoul(argv[1], NULL, 16);
603         boot_device = argv[2];
604         break;
605     case 4:
606         addr = simple_strtoul(argv[1], NULL, 16);
607         boot_device = argv[2];
608         offset = simple_strtoul(argv[3], NULL, 16);
609         break;
610     default:
611 #if (CONFIG_COMMANDS & CFG_CMD_JFFS2) && defined(CONFIG_JFFS2_CMDLINE)
612 usage:
613 #endif
614         printf("Usage:\n%s\n", cmdtp->usage);
615         SHOW_BOOT_PROGRESS(-1);
616         return 1;
617     }
618 
619     if (!boot_device) {
620         puts("\n** No boot device **\n");
621         SHOW_BOOT_PROGRESS(-1);
622         return 1;
623     }
624 
625     idx = simple_strtoul(boot_device, NULL, 16);
626 
627     if (idx < 0 || idx >= CFG_MAX_NAND_DEVICE || !nand_info[idx].name) {
628         printf("\n** Device %d not available\n", idx);
629         SHOW_BOOT_PROGRESS(-1);
630         return 1;
631     }
632 
633     return nand_load_image(cmdtp, &nand_info[idx], offset, addr, argv[0]);
634 }
635 
636 U_BOOT_CMD(nboot, 4, 1, do_nandboot,
637     "nboot   - boot from NAND device\n",
638     "[partition] | [[[loadAddr] dev] offset]\n");
639 
640 #endif              /* (CONFIG_COMMANDS & CFG_CMD_NAND) */
641 
642 #else /* CFG_NAND_LEGACY */
643 /*
644  *
645  * Legacy NAND support - to be phased out
646  *
647  */
648 #include <command.h>
649 #include <malloc.h>
650 #include <asm/io.h>
651 #include <watchdog.h>
652 
653 #ifdef CONFIG_SHOW_BOOT_PROGRESS
654 # include <status_led.h>
655 # define SHOW_BOOT_PROGRESS(arg)    show_boot_progress(arg)
656 #else
657 # define SHOW_BOOT_PROGRESS(arg)
658 #endif
659 
660 #if (CONFIG_COMMANDS & CFG_CMD_NAND)
661 #include <linux/mtd/nand_legacy.h>
662 #if 0
663 #include <linux/mtd/nand_ids.h>
664 #include <jffs2/jffs2.h>
665 #endif
666 
667 #ifdef CONFIG_OMAP1510
668 void archflashwp(void *archdata, int wp);
669 #endif
670 
671 #define ROUND_DOWN(value,boundary)      ((value) & (~((boundary)-1)))
672 
673 #undef  NAND_DEBUG
674 #undef  PSYCHO_DEBUG
675 
676 /* ****************** WARNING *********************
677  * When ALLOW_ERASE_BAD_DEBUG is non-zero the erase command will
678  * erase (or at least attempt to erase) blocks that are marked
679  * bad. This can be very handy if you are _sure_ that the block
680  * is OK, say because you marked a good block bad to test bad
681  * block handling and you are done testing, or if you have
682  * accidentally marked blocks bad.
683  *
684  * Erasing factory marked bad blocks is a _bad_ idea. If the
685  * erase succeeds there is no reliable way to find them again,
686  * and attempting to program or erase bad blocks can affect
687  * the data in _other_ (good) blocks.
688  */
689 #define  ALLOW_ERASE_BAD_DEBUG 0
690 
691 #define CONFIG_MTD_NAND_ECC  /* enable ECC */
692 #define CONFIG_MTD_NAND_ECC_JFFS2
693 
694 /* bits for nand_legacy_rw() `cmd'; or together as needed */
695 #define NANDRW_READ 0x01
696 #define NANDRW_WRITE    0x00
697 #define NANDRW_JFFS2    0x02
698 #define NANDRW_JFFS2_SKIP   0x04
699 
700 /*
701  * Imports from nand_legacy.c
702  */
703 extern struct nand_chip nand_dev_desc[CFG_MAX_NAND_DEVICE];
704 extern int curr_device;
705 extern int nand_legacy_erase(struct nand_chip *nand, size_t ofs,
706                 size_t len, int clean);
707 extern int nand_legacy_rw(struct nand_chip *nand, int cmd, size_t start,
708              size_t len, size_t *retlen, u_char *buf);
709 extern void nand_print(struct nand_chip *nand);
710 extern void nand_print_bad(struct nand_chip *nand);
711 extern int nand_read_oob(struct nand_chip *nand, size_t ofs,
712                    size_t len, size_t *retlen, u_char *buf);
713 extern int nand_write_oob(struct nand_chip *nand, size_t ofs,
714                 size_t len, size_t *retlen, const u_char *buf);
715 
716 
717 int do_nand (cmd_tbl_t *cmdtp, int flag, int argc, char *argv[])
718 {
719     int rcode = 0;
720 
721     switch (argc) {
722     case 0:
723     case 1:
724     printf ("Usage:\n%s\n", cmdtp->usage);
725     return 1;
726     case 2:
727     if (strcmp(argv[1],"info") == 0) {
728         int i;
729 
730         putc ('\n');
731 
732         for (i=0; i<CFG_MAX_NAND_DEVICE; ++i) {
733             if(nand_dev_desc[i].ChipID == NAND_ChipID_UNKNOWN)
734                 continue; /* list only known devices */
735             printf ("Device %d: ", i);
736             nand_print(&nand_dev_desc[i]);
737         }
738         return 0;
739 
740     } else if (strcmp(argv[1],"device") == 0) {
741         if ((curr_device < 0) || (curr_device >= CFG_MAX_NAND_DEVICE)) {
742             puts ("\nno devices available\n");
743             return 1;
744         }
745         printf ("\nDevice %d: ", curr_device);
746         nand_print(&nand_dev_desc[curr_device]);
747         return 0;
748 
749     } else if (strcmp(argv[1],"bad") == 0) {
750         if ((curr_device < 0) || (curr_device >= CFG_MAX_NAND_DEVICE)) {
751             puts ("\nno devices available\n");
752             return 1;
753         }
754         printf ("\nDevice %d bad blocks:\n", curr_device);
755         nand_print_bad(&nand_dev_desc[curr_device]);
756         return 0;
757 
758     }
759     printf ("Usage:\n%s\n", cmdtp->usage);
760     return 1;
761     case 3:
762     if (strcmp(argv[1],"device") == 0) {
763         int dev = (int)simple_strtoul(argv[2], NULL, 10);
764 
765         printf ("\nDevice %d: ", dev);
766         if (dev >= CFG_MAX_NAND_DEVICE) {
767             puts ("unknown device\n");
768             return 1;
769         }
770         nand_print(&nand_dev_desc[dev]);
771         /*nand_print (dev);*/
772 
773         if (nand_dev_desc[dev].ChipID == NAND_ChipID_UNKNOWN) {
774             return 1;
775         }
776 
777         curr_device = dev;
778 
779         puts ("... is now current device\n");
780 
781         return 0;
782     }
783     else if (strcmp(argv[1],"erase") == 0 && strcmp(argv[2], "clean") == 0) {
784         struct nand_chip* nand = &nand_dev_desc[curr_device];
785         ulong off = 0;
786         ulong size = nand->totlen;
787         int ret;
788 
789         printf ("\nNAND erase: device %d offset %ld, size %ld ... ",
790             curr_device, off, size);
791 
792         ret = nand_legacy_erase (nand, off, size, 1);
793 
794         printf("%s\n", ret ? "ERROR" : "OK");
795 
796         return ret;
797     }
798 
799     printf ("Usage:\n%s\n", cmdtp->usage);
800     return 1;
801     default:
802     /* at least 4 args */
803 
804     if (strncmp(argv[1], "read", 4) == 0 ||
805         strncmp(argv[1], "write", 5) == 0) {
806         ulong addr = simple_strtoul(argv[2], NULL, 16);
807         ulong off  = simple_strtoul(argv[3], NULL, 16);
808         ulong size = simple_strtoul(argv[4], NULL, 16);
809         int cmd    = (strncmp(argv[1], "read", 4) == 0) ?
810                 NANDRW_READ : NANDRW_WRITE;
811         int ret, total;
812         char* cmdtail = strchr(argv[1], '.');
813 
814         if (cmdtail && !strncmp(cmdtail, ".oob", 2)) {
815             /* read out-of-band data */
816             if (cmd & NANDRW_READ) {
817                 ret = nand_read_oob(nand_dev_desc + curr_device,
818                             off, size, (size_t *)&total,
819                             (u_char*)addr);
820             }
821             else {
822                 ret = nand_write_oob(nand_dev_desc + curr_device,
823                              off, size, (size_t *)&total,
824                              (u_char*)addr);
825             }
826             return ret;
827         }
828         else if (cmdtail && !strncmp(cmdtail, ".jffs2", 2))
829             cmd |= NANDRW_JFFS2;    /* skip bad blocks */
830         else if (cmdtail && !strncmp(cmdtail, ".jffs2s", 2)) {
831             cmd |= NANDRW_JFFS2;    /* skip bad blocks (on read too) */
832             if (cmd & NANDRW_READ)
833                 cmd |= NANDRW_JFFS2_SKIP;   /* skip bad blocks (on read too) */
834         }
835 #ifdef SXNI855T
836         /* need ".e" same as ".j" for compatibility with older units */
837         else if (cmdtail && !strcmp(cmdtail, ".e"))
838             cmd |= NANDRW_JFFS2;    /* skip bad blocks */
839 #endif
840 #ifdef CFG_NAND_SKIP_BAD_DOT_I
841         /* need ".i" same as ".jffs2s" for compatibility with older units (esd) */
842         /* ".i" for image -> read skips bad block (no 0xff) */
843         else if (cmdtail && !strcmp(cmdtail, ".i")) {
844             cmd |= NANDRW_JFFS2;    /* skip bad blocks (on read too) */
845             if (cmd & NANDRW_READ)
846                 cmd |= NANDRW_JFFS2_SKIP;   /* skip bad blocks (on read too) */
847         }
848 #endif /* CFG_NAND_SKIP_BAD_DOT_I */
849         else if (cmdtail) {
850             printf ("Usage:\n%s\n", cmdtp->usage);
851             return 1;
852         }
853 
854         printf ("\nNAND %s: device %d offset %ld, size %ld ...\n",
855             (cmd & NANDRW_READ) ? "read" : "write",
856             curr_device, off, size);
857 
858         ret = nand_legacy_rw(nand_dev_desc + curr_device, cmd, off, size,
859                  (size_t *)&total, (u_char*)addr);
860 
861         printf (" %d bytes %s: %s\n", total,
862             (cmd & NANDRW_READ) ? "read" : "written",
863             ret ? "ERROR" : "OK");
864 
865         return ret;
866     } else if (strcmp(argv[1],"erase") == 0 &&
867            (argc == 4 || strcmp("clean", argv[2]) == 0)) {
868         int clean = argc == 5;
869         ulong off = simple_strtoul(argv[2 + clean], NULL, 16);
870         ulong size = simple_strtoul(argv[3 + clean], NULL, 16);
871         int ret;
872 
873         printf ("\nNAND erase: device %d offset %ld, size %ld ...\n",
874             curr_device, off, size);
875 
876         ret = nand_legacy_erase (nand_dev_desc + curr_device,
877                     off, size, clean);
878 
879         printf("%s\n", ret ? "ERROR" : "OK");
880 
881         return ret;
882     } else {
883         printf ("Usage:\n%s\n", cmdtp->usage);
884         rcode = 1;
885     }
886 
887     return rcode;
888     }
889 }
890 
891 U_BOOT_CMD(
892     nand,   5,  1,  do_nand,
893     "nand    - legacy NAND sub-system\n",
894     "info  - show available NAND devices\n"
895     "nand device [dev] - show or set current device\n"
896     "nand read[.jffs2[s]]  addr off size\n"
897     "nand write[.jffs2] addr off size - read/write `size' bytes starting\n"
898     "    at offset `off' to/from memory address `addr'\n"
899     "nand erase [clean] [off size] - erase `size' bytes from\n"
900     "    offset `off' (entire device if not specified)\n"
901     "nand bad - show bad blocks\n"
902     "nand read.oob addr off size - read out-of-band data\n"
903     "nand write.oob addr off size - read out-of-band data\n"
904 );
905 
906 int do_nandboot (cmd_tbl_t *cmdtp, int flag, int argc, char *argv[])
907 {
908     char *boot_device = NULL;
909     char *ep;
910     int dev;
911     ulong cnt;
912     ulong addr;
913     ulong offset = 0;
914     image_header_t *hdr;
915     int rcode = 0;
916     switch (argc) {
917     case 1:
918         addr = CFG_LOAD_ADDR;
919         boot_device = getenv ("bootdevice");
920         break;
921     case 2:
922         addr = simple_strtoul(argv[1], NULL, 16);
923         boot_device = getenv ("bootdevice");
924         break;
925     case 3:
926         addr = simple_strtoul(argv[1], NULL, 16);
927         boot_device = argv[2];
928         break;
929     case 4:
930         addr = simple_strtoul(argv[1], NULL, 16);
931         boot_device = argv[2];
932         offset = simple_strtoul(argv[3], NULL, 16);
933         break;
934     default:
935         printf ("Usage:\n%s\n", cmdtp->usage);
936         SHOW_BOOT_PROGRESS (-1);
937         return 1;
938     }
939 
940     if (!boot_device) {
941         puts ("\n** No boot device **\n");
942         SHOW_BOOT_PROGRESS (-1);
943         return 1;
944     }
945 
946     dev = simple_strtoul(boot_device, &ep, 16);
947 
948     if ((dev >= CFG_MAX_NAND_DEVICE) ||
949         (nand_dev_desc[dev].ChipID == NAND_ChipID_UNKNOWN)) {
950         printf ("\n** Device %d not available\n", dev);
951         SHOW_BOOT_PROGRESS (-1);
952         return 1;
953     }
954 
955     printf ("\nLoading from device %d: %s at 0x%lx (offset 0x%lx)\n",
956         dev, nand_dev_desc[dev].name, nand_dev_desc[dev].IO_ADDR,
957         offset);
958 
959     if (nand_legacy_rw (nand_dev_desc + dev, NANDRW_READ, offset,
960             SECTORSIZE, NULL, (u_char *)addr)) {
961         printf ("** Read error on %d\n", dev);
962         SHOW_BOOT_PROGRESS (-1);
963         return 1;
964     }
965 
966     hdr = (image_header_t *)addr;
967 
968     if (ntohl(hdr->ih_magic) == IH_MAGIC) {
969 
970         print_image_hdr (hdr);
971 
972         cnt = (ntohl(hdr->ih_size) + sizeof(image_header_t));
973         cnt -= SECTORSIZE;
974     } else {
975         printf ("\n** Bad Magic Number 0x%x **\n", ntohl(hdr->ih_magic));
976         SHOW_BOOT_PROGRESS (-1);
977         return 1;
978     }
979 
980     if (nand_legacy_rw (nand_dev_desc + dev, NANDRW_READ,
981             offset + SECTORSIZE, cnt, NULL,
982             (u_char *)(addr+SECTORSIZE))) {
983         printf ("** Read error on %d\n", dev);
984         SHOW_BOOT_PROGRESS (-1);
985         return 1;
986     }
987 
988     /* Loading ok, update default load address */
989 
990     load_addr = addr;
991 
992     /* Check if we should attempt an auto-start */
993     if (((ep = getenv("autostart")) != NULL) && (strcmp(ep,"yes") == 0)) {
994         char *local_args[2];
995         extern int do_bootm (cmd_tbl_t *, int, int, char *[]);
996 
997         local_args[0] = argv[0];
998         local_args[1] = NULL;
999 
1000         printf ("Automatic boot of image at addr 0x%08lx ...\n", addr);
1001 
1002         do_bootm (cmdtp, 0, 1, local_args);
1003         rcode = 1;
1004     }
1005     return rcode;
1006 }
1007 
1008 U_BOOT_CMD(
1009     nboot,  4,  1,  do_nandboot,
1010     "nboot   - boot from NAND device\n",
1011     "loadAddr dev\n"
1012 );
1013 
1014 #endif /* (CONFIG_COMMANDS & CFG_CMD_NAND) */
1015 
1016 #endif /* CFG_NAND_LEGACY */
