01 /*
02  * (C) Copyright 2000-2004
03  * Wolfgang Denk, DENX Software Engineering, wd@denx.de.
04  *
05  * See file CREDITS for list of people who contributed to this
06  * project.
07  *
08  * This program is free software; you can redistribute it and/or
09  * modify it under the terms of the GNU General Public License as
10  * published by the Free Software Foundation; either version 2 of
11  * the License, or (at your option) any later version.
12  *
13  * This program is distributed in the hope that it will be useful,
14  * but WITHOUT ANY WARRANTY; without even the implied warranty of
15  * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
16  * GNU General Public License for more details.
17  *
18  * You should have received a copy of the GNU General Public License
19  * along with this program; if not, write to the Free Software
20  * Foundation, Inc., 59 Temple Place, Suite 330, Boston,
21  * MA 02111-1307 USA
22  */
23 
24 /*
25  * Serial up- and download support
26  */
27 #include <common.h>
28 #include <command.h>
29 #include <s_record.h>
30 #include <net.h>
31 #include <exports.h>
32 #include <xyzModem.h>
33 
34 DECLARE_GLOBAL_DATA_PTR;
35 
36 #if (CONFIG_COMMANDS & CFG_CMD_LOADB)
37 /* support xmodem, www.arm9.net */
38 static ulong load_serial_xmodem (ulong offset);
39 static ulong load_serial_ymodem (ulong offset);
40 #endif
41 
42 #if (CONFIG_COMMANDS & CFG_CMD_LOADS)
43 static ulong load_serial (ulong offset);
44 static int read_record (char *buf, ulong len);
45 # if (CONFIG_COMMANDS & CFG_CMD_SAVES)
46 static int save_serial (ulong offset, ulong size);
47 static int write_record (char *buf);
48 # endif /* CFG_CMD_SAVES */
49 
50 static int do_echo = 1;
51 #endif /* CFG_CMD_LOADS */
52 
53 /* -------------------------------------------------------------------- */
54 
55 #if (CONFIG_COMMANDS & CFG_CMD_LOADS)
56 int do_load_serial (cmd_tbl_t *cmdtp, int flag, int argc, char *argv[])
57 {
58     ulong offset = 0;
59     ulong addr;
60     int i;
61     char *env_echo;
62     int rcode = 0;
63 #ifdef  CFG_LOADS_BAUD_CHANGE
64     int load_baudrate, current_baudrate;
65 
66     load_baudrate = current_baudrate = gd->baudrate;
67 #endif
68 
69     if (((env_echo = getenv("loads_echo")) != NULL) && (*env_echo == '1')) {
70         do_echo = 1;
71     } else {
72         do_echo = 0;
73     }
74 
75 #ifdef  CFG_LOADS_BAUD_CHANGE
76     if (argc >= 2) {
77         offset = simple_strtoul(argv[1], NULL, 16);
78     }
79     if (argc == 3) {
80         load_baudrate = (int)simple_strtoul(argv[2], NULL, 10);
81 
82         /* default to current baudrate */
83         if (load_baudrate == 0)
84             load_baudrate = current_baudrate;
85     }
86     if (load_baudrate != current_baudrate) {
87         printf ("## Switch baudrate to %d bps and press ENTER ...\n",
88             load_baudrate);
89         udelay(50000);
90         gd->baudrate = load_baudrate;
91         serial_setbrg ();
92         udelay(50000);
93         for (;;) {
94             if (getc() == '\r')
95                 break;
96         }
97     }
98 #else   /* ! CFG_LOADS_BAUD_CHANGE */
99     if (argc == 2) {
100         offset = simple_strtoul(argv[1], NULL, 16);
101     }
102 #endif  /* CFG_LOADS_BAUD_CHANGE */
103 
104     printf ("## Ready for S-Record download ...\n");
105 
106     addr = load_serial (offset);
107 
108     /*
109      * Gather any trailing characters (for instance, the ^D which
110      * is sent by 'cu' after sending a file), and give the
111      * box some time (100 * 1 ms)
112      */
113     for (i=0; i<100; ++i) {
114         if (tstc()) {
115             (void) getc();
116         }
117         udelay(1000);
118     }
119 
120     if (addr == ~0) {
121         printf ("## S-Record download aborted\n");
122         rcode = 1;
123     } else {
124         printf ("## Start Addr      = 0x%08lX\n", addr);
125         load_addr = addr;
126     }
127 
128 #ifdef  CFG_LOADS_BAUD_CHANGE
129     if (load_baudrate != current_baudrate) {
130         printf ("## Switch baudrate to %d bps and press ESC ...\n",
131             current_baudrate);
132         udelay (50000);
133         gd->baudrate = current_baudrate;
134         serial_setbrg ();
135         udelay (50000);
136         for (;;) {
137             if (getc() == 0x1B) /* ESC */
138                 break;
139         }
140     }
141 #endif
142     return rcode;
143 }
144 
145 static ulong
146 load_serial (ulong offset)
147 {
148     char    record[SREC_MAXRECLEN + 1]; /* buffer for one S-Record  */
149     char    binbuf[SREC_MAXBINLEN];     /* buffer for binary data   */
150     int binlen;             /* no. of data bytes in S-Rec.  */
151     int type;               /* return code for record type  */
152     ulong   addr;               /* load address from S-Record   */
153     ulong   size;               /* number of bytes transferred  */
154     char    buf[32];
155     ulong   store_addr;
156     ulong   start_addr = ~0;
157     ulong   end_addr   =  0;
158     int line_count =  0;
159 
160     while (read_record(record, SREC_MAXRECLEN + 1) >= 0) {
161         type = srec_decode (record, &binlen, &addr, binbuf);
162 
163         if (type < 0) {
164             return (~0);        /* Invalid S-Record     */
165         }
166 
167         switch (type) {
168         case SREC_DATA2:
169         case SREC_DATA3:
170         case SREC_DATA4:
171             store_addr = addr + offset;
172 #ifndef CFG_NO_FLASH
173             if (addr2info(store_addr)) {
174             int rc;
175 
176             rc = flash_write((char *)binbuf,store_addr,binlen);
177             if (rc != 0) {
178                 flash_perror (rc);
179                 return (~0);
180             }
181             } else
182 #endif
183             {
184             memcpy ((char *)(store_addr), binbuf, binlen);
185             }
186             if ((store_addr) < start_addr)
187             start_addr = store_addr;
188             if ((store_addr + binlen - 1) > end_addr)
189             end_addr = store_addr + binlen - 1;
190             break;
191         case SREC_END2:
192         case SREC_END3:
193         case SREC_END4:
194             udelay (10000);
195             size = end_addr - start_addr + 1;
196             printf ("\n"
197                 "## First Load Addr = 0x%08lX\n"
198                 "## Last  Load Addr = 0x%08lX\n"
199                 "## Total Size      = 0x%08lX = %ld Bytes\n",
200                 start_addr, end_addr, size, size
201             );
202             flush_cache (start_addr, size);
203             sprintf(buf, "%lX", size);
204             setenv("filesize", buf);
205             return (addr);
206         case SREC_START:
207             break;
208         default:
209             break;
210         }
211         if (!do_echo) { /* print a '.' every 100 lines */
212             if ((++line_count % 100) == 0)
213                 putc ('.');
214         }
215     }
216 
217     return (~0);            /* Download aborted     */
218 }
219 
220 static int
221 read_record (char *buf, ulong len)
222 {
223     char *p;
224     char c;
225 
226     --len;  /* always leave room for terminating '\0' byte */
227 
228     for (p=buf; p < buf+len; ++p) {
229         c = getc();     /* read character       */
230         if (do_echo)
231             putc (c);   /* ... and echo it      */
232 
233         switch (c) {
234         case '\r':
235         case '\n':
236             *p = '\0';
237             return (p - buf);
238         case '\0':
239         case 0x03:          /* ^C - Control C       */
240             return (-1);
241         default:
242             *p = c;
243         }
244 
245         /* Check for the console hangup (if any different from serial) */
246         if (gd->jt[XF_getc] != getc) {
247         if (ctrlc()) {
248             return (-1);
249         }
250         }
251     }
252 
253     /* line too long - truncate */
254     *p = '\0';
255     return (p - buf);
256 }
257 
258 #if (CONFIG_COMMANDS & CFG_CMD_SAVES)
259 
260 int do_save_serial (cmd_tbl_t *cmdtp, int flag, int argc, char *argv[])
261 {
262     ulong offset = 0;
263     ulong size   = 0;
264 #ifdef  CFG_LOADS_BAUD_CHANGE
265     int save_baudrate, current_baudrate;
266 
267     save_baudrate = current_baudrate = gd->baudrate;
268 #endif
269 
270     if (argc >= 2) {
271         offset = simple_strtoul(argv[1], NULL, 16);
272     }
273 #ifdef  CFG_LOADS_BAUD_CHANGE
274     if (argc >= 3) {
275         size = simple_strtoul(argv[2], NULL, 16);
276     }
277     if (argc == 4) {
278         save_baudrate = (int)simple_strtoul(argv[3], NULL, 10);
279 
280         /* default to current baudrate */
281         if (save_baudrate == 0)
282             save_baudrate = current_baudrate;
283     }
284     if (save_baudrate != current_baudrate) {
285         printf ("## Switch baudrate to %d bps and press ENTER ...\n",
286             save_baudrate);
287         udelay(50000);
288         gd->baudrate = save_baudrate;
289         serial_setbrg ();
290         udelay(50000);
291         for (;;) {
292             if (getc() == '\r')
293                 break;
294         }
295     }
296 #else   /* ! CFG_LOADS_BAUD_CHANGE */
297     if (argc == 3) {
298         size = simple_strtoul(argv[2], NULL, 16);
299     }
300 #endif  /* CFG_LOADS_BAUD_CHANGE */
301 
302     printf ("## Ready for S-Record upload, press ENTER to proceed ...\n");
303     for (;;) {
304         if (getc() == '\r')
305             break;
306     }
307     if(save_serial (offset, size)) {
308         printf ("## S-Record upload aborted\n");
309     } else {
310         printf ("## S-Record upload complete\n");
311     }
312 #ifdef  CFG_LOADS_BAUD_CHANGE
313     if (save_baudrate != current_baudrate) {
314         printf ("## Switch baudrate to %d bps and press ESC ...\n",
315             (int)current_baudrate);
316         udelay (50000);
317         gd->baudrate = current_baudrate;
318         serial_setbrg ();
319         udelay (50000);
320         for (;;) {
321             if (getc() == 0x1B) /* ESC */
322                 break;
323         }
324     }
325 #endif
326     return 0;
327 }
328 
329 #define SREC3_START             "S0030000FC\n"
330 #define SREC3_FORMAT            "S3%02X%08lX%s%02X\n"
331 #define SREC3_END               "S70500000000FA\n"
332 #define SREC_BYTES_PER_RECORD   16
333 
334 static int save_serial (ulong address, ulong count)
335 {
336     int i, c, reclen, checksum, length;
337     char *hex = "0123456789ABCDEF";
338     char    record[2*SREC_BYTES_PER_RECORD+16]; /* buffer for one S-Record  */
339     char    data[2*SREC_BYTES_PER_RECORD+1];    /* buffer for hex data  */
340 
341     reclen = 0;
342     checksum  = 0;
343 
344     if(write_record(SREC3_START))           /* write the header */
345         return (-1);
346     do {
347         if(count) {                     /* collect hex data in the buffer  */
348             c = *(volatile uchar*)(address + reclen);   /* get one byte    */
349             checksum += c;                          /* accumulate checksum */
350             data[2*reclen]   = hex[(c>>4)&0x0f];
351             data[2*reclen+1] = hex[c & 0x0f];
352             data[2*reclen+2] = '\0';
353             ++reclen;
354             --count;
355         }
356         if(reclen == SREC_BYTES_PER_RECORD || count == 0) {
357             /* enough data collected for one record: dump it */
358             if(reclen) {    /* build & write a data record: */
359                 /* address + data + checksum */
360                 length = 4 + reclen + 1;
361 
362                 /* accumulate length bytes into checksum */
363                 for(i = 0; i < 2; i++)
364                     checksum += (length >> (8*i)) & 0xff;
365 
366                 /* accumulate address bytes into checksum: */
367                 for(i = 0; i < 4; i++)
368                     checksum += (address >> (8*i)) & 0xff;
369 
370                 /* make proper checksum byte: */
371                 checksum = ~checksum & 0xff;
372 
373                 /* output one record: */
374                 sprintf(record, SREC3_FORMAT, length, address, data, checksum);
375                 if(write_record(record))
376                     return (-1);
377             }
378             address  += reclen;  /* increment address */
379             checksum  = 0;
380             reclen    = 0;
381         }
382     }
383     while(count);
384     if(write_record(SREC3_END)) /* write the final record */
385         return (-1);
386     return(0);
387 }
388 
389 static int
390 write_record (char *buf)
391 {
392     char c;
393 
394     while((c = *buf++))
395         putc(c);
396 
397     /* Check for the console hangup (if any different from serial) */
398 
399     if (ctrlc()) {
400         return (-1);
401     }
402     return (0);
403 }
404 # endif /* CFG_CMD_SAVES */
405 
406 #endif  /* CFG_CMD_LOADS */
407 
408 
409 #if (CONFIG_COMMANDS & CFG_CMD_LOADB)  /* loadb command (load binary) included */
410 
411 #define XON_CHAR        17
412 #define XOFF_CHAR       19
413 #define START_CHAR      0x01
414 #define ETX_CHAR    0x03
415 #define END_CHAR        0x0D
416 #define SPACE           0x20
417 #define K_ESCAPE        0x23
418 #define SEND_TYPE       'S'
419 #define DATA_TYPE       'D'
420 #define ACK_TYPE        'Y'
421 #define NACK_TYPE       'N'
422 #define BREAK_TYPE      'B'
423 #define tochar(x) ((char) (((x) + SPACE) & 0xff))
424 #define untochar(x) ((int) (((x) - SPACE) & 0xff))
425 
426 extern int os_data_count;
427 extern int os_data_header[8];
428 
429 static void set_kerm_bin_mode(unsigned long *);
430 static int k_recv(void);
431 static ulong load_serial_bin (ulong offset);
432 
433 
434 char his_eol;        /* character he needs at end of packet */
435 int  his_pad_count;  /* number of pad chars he needs */
436 char his_pad_char;   /* pad chars he needs */
437 char his_quote;      /* quote chars he'll use */
438 
439 int do_load_serial_bin (cmd_tbl_t *cmdtp, int flag, int argc, char *argv[])
440 {
441     ulong offset = 0;
442     ulong addr;
443     int load_baudrate, current_baudrate;
444     int rcode = 0;
445     char *s;
446 
447     /* pre-set offset from CFG_LOAD_ADDR */
448     offset = CFG_LOAD_ADDR;
449 
450     /* pre-set offset from $loadaddr */
451     if ((s = getenv("loadaddr")) != NULL) {
452         offset = simple_strtoul(s, NULL, 16);
453     }
454 
455     load_baudrate = current_baudrate = gd->baudrate;
456 
457     if (argc >= 2) {
458         offset = simple_strtoul(argv[1], NULL, 16);
459     }
460     if (argc == 3) {
461         load_baudrate = (int)simple_strtoul(argv[2], NULL, 10);
462 
463         /* default to current baudrate */
464         if (load_baudrate == 0)
465             load_baudrate = current_baudrate;
466     }
467 
468     if (load_baudrate != current_baudrate) {
469         printf ("## Switch baudrate to %d bps and press ENTER ...\n",
470             load_baudrate);
471         udelay(50000);
472         gd->baudrate = load_baudrate;
473         serial_setbrg ();
474         udelay(50000);
475         for (;;) {
476             if (getc() == '\r')
477                 break;
478         }
479     }
480 
481     /* support xmodem, www.arm9.net */
482     if (strcmp(argv[0],"loadx")==0) {
483         printf ("## Ready for binary (xmodem) download "
484             "to 0x%08lX at %d bps...\n",
485             offset,
486             load_baudrate);
487 
488         addr = load_serial_xmodem (offset);
489 
490     } else if (strcmp(argv[0],"loady")==0) {
491         printf ("## Ready for binary (ymodem) download "
492             "to 0x%08lX at %d bps...\n",
493             offset,
494             load_baudrate);
495 
496         addr = load_serial_ymodem (offset);
497 
498     } else {
499 
500         printf ("## Ready for binary (kermit) download "
501             "to 0x%08lX at %d bps...\n",
502             offset,
503             load_baudrate);
504         addr = load_serial_bin (offset);
505 
506         if (addr == ~0) {
507             load_addr = 0;
508             printf ("## Binary (kermit) download aborted\n");
509             rcode = 1;
510         } else {
511             printf ("## Start Addr      = 0x%08lX\n", addr);
512             load_addr = addr;
513         }
514     }
515     if (load_baudrate != current_baudrate) {
516         printf ("## Switch baudrate to %d bps and press ESC ...\n",
517             current_baudrate);
518         udelay (50000);
519         gd->baudrate = current_baudrate;
520         serial_setbrg ();
521         udelay (50000);
522         for (;;) {
523             if (getc() == 0x1B) /* ESC */
524                 break;
525         }
526     }
527 
528 #ifdef CONFIG_AUTOSCRIPT
529     if (load_addr) {
530         char *s;
531 
532         if (((s = getenv("autoscript")) != NULL) && (strcmp(s,"yes") == 0)) {
533             printf("Running autoscript at addr 0x%08lX ...\n", load_addr);
534             rcode = autoscript (load_addr);
535         }
536     }
537 #endif
538     return rcode;
539 }
540 
541 
542 static ulong load_serial_bin (ulong offset)
543 {
544     int size, i;
545     char buf[32];
546 
547     set_kerm_bin_mode ((ulong *) offset);
548     size = k_recv ();
549 
550     /*
551      * Gather any trailing characters (for instance, the ^D which
552      * is sent by 'cu' after sending a file), and give the
553      * box some time (100 * 1 ms)
554      */
555     for (i=0; i<100; ++i) {
556         if (tstc()) {
557             (void) getc();
558         }
559         udelay(1000);
560     }
561 
562     flush_cache (offset, size);
563 
564     printf("## Total Size      = 0x%08x = %d Bytes\n", size, size);
565     sprintf(buf, "%X", size);
566     setenv("filesize", buf);
567 
568     return offset;
569 }
570 
571 void send_pad (void)
572 {
573     int count = his_pad_count;
574 
575     while (count-- > 0)
576         putc (his_pad_char);
577 }
578 
579 /* converts escaped kermit char to binary char */
580 char ktrans (char in)
581 {
582     if ((in & 0x60) == 0x40) {
583         return (char) (in & ~0x40);
584     } else if ((in & 0x7f) == 0x3f) {
585         return (char) (in | 0x40);
586     } else
587         return in;
588 }
589 
590 int chk1 (char *buffer)
591 {
592     int total = 0;
593 
594     while (*buffer) {
595         total += *buffer++;
596     }
597     return (int) ((total + ((total >> 6) & 0x03)) & 0x3f);
598 }
599 
600 void s1_sendpacket (char *packet)
601 {
602     send_pad ();
603     while (*packet) {
604         putc (*packet++);
605     }
606 }
607 
608 static char a_b[24];
609 void send_ack (int n)
610 {
611     a_b[0] = START_CHAR;
612     a_b[1] = tochar (3);
613     a_b[2] = tochar (n);
614     a_b[3] = ACK_TYPE;
615     a_b[4] = '\0';
616     a_b[4] = tochar (chk1 (&a_b[1]));
617     a_b[5] = his_eol;
618     a_b[6] = '\0';
619     s1_sendpacket (a_b);
620 }
621 
622 void send_nack (int n)
623 {
624     a_b[0] = START_CHAR;
625     a_b[1] = tochar (3);
626     a_b[2] = tochar (n);
627     a_b[3] = NACK_TYPE;
628     a_b[4] = '\0';
629     a_b[4] = tochar (chk1 (&a_b[1]));
630     a_b[5] = his_eol;
631     a_b[6] = '\0';
632     s1_sendpacket (a_b);
633 }
634 
635 
636 /* os_data_* takes an OS Open image and puts it into memory, and
637    puts the boot header in an array named os_data_header
638 
639    if image is binary, no header is stored in os_data_header.
640 */
641 void (*os_data_init) (void);
642 void (*os_data_char) (char new_char);
643 static int os_data_state, os_data_state_saved;
644 int os_data_count;
645 static int os_data_count_saved;
646 static char *os_data_addr, *os_data_addr_saved;
647 static char *bin_start_address;
648 int os_data_header[8];
649 static void bin_data_init (void)
650 {
651     os_data_state = 0;
652     os_data_count = 0;
653     os_data_addr = bin_start_address;
654 }
655 static void os_data_save (void)
656 {
657     os_data_state_saved = os_data_state;
658     os_data_count_saved = os_data_count;
659     os_data_addr_saved = os_data_addr;
660 }
661 static void os_data_restore (void)
662 {
663     os_data_state = os_data_state_saved;
664     os_data_count = os_data_count_saved;
665     os_data_addr = os_data_addr_saved;
666 }
667 static void bin_data_char (char new_char)
668 {
669     switch (os_data_state) {
670     case 0:                 /* data */
671         *os_data_addr++ = new_char;
672         --os_data_count;
673         break;
674     }
675 }
676 static void set_kerm_bin_mode (unsigned long *addr)
677 {
678     bin_start_address = (char *) addr;
679     os_data_init = bin_data_init;
680     os_data_char = bin_data_char;
681 }
682 
683 
684 /* k_data_* simply handles the kermit escape translations */
685 static int k_data_escape, k_data_escape_saved;
686 void k_data_init (void)
687 {
688     k_data_escape = 0;
689     os_data_init ();
690 }
691 void k_data_save (void)
692 {
693     k_data_escape_saved = k_data_escape;
694     os_data_save ();
695 }
696 void k_data_restore (void)
697 {
698     k_data_escape = k_data_escape_saved;
699     os_data_restore ();
700 }
701 void k_data_char (char new_char)
702 {
703     if (k_data_escape) {
704         /* last char was escape - translate this character */
705         os_data_char (ktrans (new_char));
706         k_data_escape = 0;
707     } else {
708         if (new_char == his_quote) {
709             /* this char is escape - remember */
710             k_data_escape = 1;
711         } else {
712             /* otherwise send this char as-is */
713             os_data_char (new_char);
714         }
715     }
716 }
717 
718 #define SEND_DATA_SIZE  20
719 char send_parms[SEND_DATA_SIZE];
720 char *send_ptr;
721 
722 /* handle_send_packet interprits the protocol info and builds and
723    sends an appropriate ack for what we can do */
724 void handle_send_packet (int n)
725 {
726     int length = 3;
727     int bytes;
728 
729     /* initialize some protocol parameters */
730     his_eol = END_CHAR;     /* default end of line character */
731     his_pad_count = 0;
732     his_pad_char = '\0';
733     his_quote = K_ESCAPE;
734 
735     /* ignore last character if it filled the buffer */
736     if (send_ptr == &send_parms[SEND_DATA_SIZE - 1])
737         --send_ptr;
738     bytes = send_ptr - send_parms;  /* how many bytes we'll process */
739     do {
740         if (bytes-- <= 0)
741             break;
742         /* handle MAXL - max length */
743         /* ignore what he says - most I'll take (here) is 94 */
744         a_b[++length] = tochar (94);
745         if (bytes-- <= 0)
746             break;
747         /* handle TIME - time you should wait for my packets */
748         /* ignore what he says - don't wait for my ack longer than 1 second */
749         a_b[++length] = tochar (1);
750         if (bytes-- <= 0)
751             break;
752         /* handle NPAD - number of pad chars I need */
753         /* remember what he says - I need none */
754         his_pad_count = untochar (send_parms[2]);
755         a_b[++length] = tochar (0);
756         if (bytes-- <= 0)
757             break;
758         /* handle PADC - pad chars I need */
759         /* remember what he says - I need none */
760         his_pad_char = ktrans (send_parms[3]);
761         a_b[++length] = 0x40;   /* He should ignore this */
762         if (bytes-- <= 0)
763             break;
764         /* handle EOL - end of line he needs */
765         /* remember what he says - I need CR */
766         his_eol = untochar (send_parms[4]);
767         a_b[++length] = tochar (END_CHAR);
768         if (bytes-- <= 0)
769             break;
770         /* handle QCTL - quote control char he'll use */
771         /* remember what he says - I'll use '#' */
772         his_quote = send_parms[5];
773         a_b[++length] = '#';
774         if (bytes-- <= 0)
775             break;
776         /* handle QBIN - 8-th bit prefixing */
777         /* ignore what he says - I refuse */
778         a_b[++length] = 'N';
779         if (bytes-- <= 0)
780             break;
781         /* handle CHKT - the clock check type */
782         /* ignore what he says - I do type 1 (for now) */
783         a_b[++length] = '1';
784         if (bytes-- <= 0)
785             break;
786         /* handle REPT - the repeat prefix */
787         /* ignore what he says - I refuse (for now) */
788         a_b[++length] = 'N';
789         if (bytes-- <= 0)
790             break;
791         /* handle CAPAS - the capabilities mask */
792         /* ignore what he says - I only do long packets - I don't do windows */
793         a_b[++length] = tochar (2); /* only long packets */
794         a_b[++length] = tochar (0); /* no windows */
795         a_b[++length] = tochar (94);    /* large packet msb */
796         a_b[++length] = tochar (94);    /* large packet lsb */
797     } while (0);
798 
799     a_b[0] = START_CHAR;
800     a_b[1] = tochar (length);
801     a_b[2] = tochar (n);
802     a_b[3] = ACK_TYPE;
803     a_b[++length] = '\0';
804     a_b[length] = tochar (chk1 (&a_b[1]));
805     a_b[++length] = his_eol;
806     a_b[++length] = '\0';
807     s1_sendpacket (a_b);
808 }
809 
810 /* k_recv receives a OS Open image file over kermit line */
811 static int k_recv (void)
812 {
813     char new_char;
814     char k_state, k_state_saved;
815     int sum;
816     int done;
817     int length;
818     int n, last_n;
819     int z = 0;
820     int len_lo, len_hi;
821 
822     /* initialize some protocol parameters */
823     his_eol = END_CHAR;     /* default end of line character */
824     his_pad_count = 0;
825     his_pad_char = '\0';
826     his_quote = K_ESCAPE;
827 
828     /* initialize the k_recv and k_data state machine */
829     done = 0;
830     k_state = 0;
831     k_data_init ();
832     k_state_saved = k_state;
833     k_data_save ();
834     n = 0;              /* just to get rid of a warning */
835     last_n = -1;
836 
837     /* expect this "type" sequence (but don't check):
838        S: send initiate
839        F: file header
840        D: data (multiple)
841        Z: end of file
842        B: break transmission
843      */
844 
845     /* enter main loop */
846     while (!done) {
847         /* set the send packet pointer to begining of send packet parms */
848         send_ptr = send_parms;
849 
850         /* With each packet, start summing the bytes starting with the length.
851            Save the current sequence number.
852            Note the type of the packet.
853            If a character less than SPACE (0x20) is received - error.
854          */
855 
856 #if 0
857         /* OLD CODE, Prior to checking sequence numbers */
858         /* first have all state machines save current states */
859         k_state_saved = k_state;
860         k_data_save ();
861 #endif
862 
863         /* get a packet */
864         /* wait for the starting character or ^C */
865         for (;;) {
866             switch (getc ()) {
867             case START_CHAR:    /* start packet */
868                 goto START;
869             case ETX_CHAR:      /* ^C waiting for packet */
870                 return (0);
871             default:
872                 ;
873             }
874         }
875 START:
876         /* get length of packet */
877         sum = 0;
878         new_char = getc ();
879         if ((new_char & 0xE0) == 0)
880             goto packet_error;
881         sum += new_char & 0xff;
882         length = untochar (new_char);
883         /* get sequence number */
884         new_char = getc ();
885         if ((new_char & 0xE0) == 0)
886             goto packet_error;
887         sum += new_char & 0xff;
888         n = untochar (new_char);
889         --length;
890 
891         /* NEW CODE - check sequence numbers for retried packets */
892         /* Note - this new code assumes that the sequence number is correctly
893          * received.  Handling an invalid sequence number adds another layer
894          * of complexity that may not be needed - yet!  At this time, I'm hoping
895          * that I don't need to buffer the incoming data packets and can write
896          * the data into memory in real time.
897          */
898         if (n == last_n) {
899             /* same sequence number, restore the previous state */
900             k_state = k_state_saved;
901             k_data_restore ();
902         } else {
903             /* new sequence number, checkpoint the download */
904             last_n = n;
905             k_state_saved = k_state;
906             k_data_save ();
907         }
908         /* END NEW CODE */
909 
910         /* get packet type */
911         new_char = getc ();
912         if ((new_char & 0xE0) == 0)
913             goto packet_error;
914         sum += new_char & 0xff;
915         k_state = new_char;
916         --length;
917         /* check for extended length */
918         if (length == -2) {
919             /* (length byte was 0, decremented twice) */
920             /* get the two length bytes */
921             new_char = getc ();
922             if ((new_char & 0xE0) == 0)
923                 goto packet_error;
924             sum += new_char & 0xff;
925             len_hi = untochar (new_char);
926             new_char = getc ();
927             if ((new_char & 0xE0) == 0)
928                 goto packet_error;
929             sum += new_char & 0xff;
930             len_lo = untochar (new_char);
931             length = len_hi * 95 + len_lo;
932             /* check header checksum */
933             new_char = getc ();
934             if ((new_char & 0xE0) == 0)
935                 goto packet_error;
936             if (new_char != tochar ((sum + ((sum >> 6) & 0x03)) & 0x3f))
937                 goto packet_error;
938             sum += new_char & 0xff;
939 /* --length; */ /* new length includes only data and block check to come */
940         }
941         /* bring in rest of packet */
942         while (length > 1) {
943             new_char = getc ();
944             if ((new_char & 0xE0) == 0)
945                 goto packet_error;
946             sum += new_char & 0xff;
947             --length;
948             if (k_state == DATA_TYPE) {
949                 /* pass on the data if this is a data packet */
950                 k_data_char (new_char);
951             } else if (k_state == SEND_TYPE) {
952                 /* save send pack in buffer as is */
953                 *send_ptr++ = new_char;
954                 /* if too much data, back off the pointer */
955                 if (send_ptr >= &send_parms[SEND_DATA_SIZE])
956                     --send_ptr;
957             }
958         }
959         /* get and validate checksum character */
960         new_char = getc ();
961         if ((new_char & 0xE0) == 0)
962             goto packet_error;
963         if (new_char != tochar ((sum + ((sum >> 6) & 0x03)) & 0x3f))
964             goto packet_error;
965         /* get END_CHAR */
966         new_char = getc ();
967         if (new_char != END_CHAR) {
968           packet_error:
969             /* restore state machines */
970             k_state = k_state_saved;
971             k_data_restore ();
972             /* send a negative acknowledge packet in */
973             send_nack (n);
974         } else if (k_state == SEND_TYPE) {
975             /* crack the protocol parms, build an appropriate ack packet */
976             handle_send_packet (n);
977         } else {
978             /* send simple acknowledge packet in */
979             send_ack (n);
980             /* quit if end of transmission */
981             if (k_state == BREAK_TYPE)
982                 done = 1;
983         }
984         ++z;
985     }
986     return ((ulong) os_data_addr - (ulong) bin_start_address);
987 }
988 
989 static int getcxmodem(void) {
990     if (tstc())
991         return (getc());
992     return -1;
993 }
994 
995 /* support xmodem, www.arm9.net */
996 static ulong load_serial_xmodem (ulong offset)
997 {
998     int size;
999     char buf[32];
1000     int err;
1001     int res;
1002     connection_info_t info;
1003     char xmodemBuf[1024];
1004     ulong store_addr = ~0;
1005     ulong addr = 0;
1006 
1007     size = 0;
1008     info.mode = xyzModem_xmodem;
1009     res = xyzModem_stream_open (&info, &err);
1010     if (!res) {
1011 
1012         while ((res =
1013             xyzModem_stream_read (xmodemBuf, 1024, &err)) > 0) {
1014             store_addr = addr + offset;
1015             size += res;
1016             addr += res;
1017 #ifndef CFG_NO_FLASH
1018             if (addr2info (store_addr)) {
1019                 int rc;
1020 
1021                 rc = flash_write ((char *) xmodemBuf,
1022                           store_addr, res);
1023                 if (rc != 0) {
1024                     flash_perror (rc);
1025                     return (~0);
1026                 }
1027             } else
1028 #endif
1029             {
1030                 memcpy ((char *) (store_addr), xmodemBuf,
1031                     res);
1032             }
1033 
1034         }
1035     } else {
1036         printf ("%s\n", xyzModem_error (err));
1037     }
1038 
1039     xyzModem_stream_close (&err);
1040     xyzModem_stream_terminate (false, &getcxmodem);
1041 
1042 
1043     flush_cache (offset, size);
1044 
1045     printf ("## Total Size      = 0x%08x = %d Bytes\n", size, size);
1046     sprintf (buf, "%X", size);
1047     setenv ("filesize", buf);
1048 
1049     return offset;
1050 }
1051 
1052 static ulong load_serial_ymodem (ulong offset)
1053 {
1054     int size;
1055     char buf[32];
1056     int err;
1057     int res;
1058     connection_info_t info;
1059     char ymodemBuf[1024];
1060     ulong store_addr = ~0;
1061     ulong addr = 0;
1062 
1063     size = 0;
1064     info.mode = xyzModem_ymodem;
1065     res = xyzModem_stream_open (&info, &err);
1066     if (!res) {
1067 
1068         while ((res =
1069             xyzModem_stream_read (ymodemBuf, 1024, &err)) > 0) {
1070             store_addr = addr + offset;
1071             size += res;
1072             addr += res;
1073 #ifndef CFG_NO_FLASH
1074             if (addr2info (store_addr)) {
1075                 int rc;
1076 
1077                 rc = flash_write ((char *) ymodemBuf,
1078                           store_addr, res);
1079                 if (rc != 0) {
1080                     flash_perror (rc);
1081                     return (~0);
1082                 }
1083             } else
1084 #endif
1085             {
1086                 memcpy ((char *) (store_addr), ymodemBuf,
1087                     res);
1088             }
1089 
1090         }
1091     } else {
1092         printf ("%s\n", xyzModem_error (err));
1093     }
1094 
1095     xyzModem_stream_close (&err);
1096     xyzModem_stream_terminate (false, &getcxmodem);
1097 
1098 
1099     flush_cache (offset, size);
1100 
1101     printf ("## Total Size      = 0x%08x = %d Bytes\n", size, size);
1102     sprintf (buf, "%X", size);
1103     setenv ("filesize", buf);
1104 
1105     return offset;
1106 }
1107 
1108 #endif  /* CFG_CMD_LOADB */
1109 
1110 /* -------------------------------------------------------------------- */
1111 
1112 #if (CONFIG_COMMANDS & CFG_CMD_LOADS)
1113 
1114 #ifdef  CFG_LOADS_BAUD_CHANGE
1115 U_BOOT_CMD(
1116     loads, 3, 0,    do_load_serial,
1117     "loads   - load S-Record file over serial line\n",
1118     "[ off ] [ baud ]\n"
1119     "    - load S-Record file over serial line"
1120     " with offset 'off' and baudrate 'baud'\n"
1121 );
1122 
1123 #else   /* ! CFG_LOADS_BAUD_CHANGE */
1124 U_BOOT_CMD(
1125     loads, 2, 0,    do_load_serial,
1126     "loads   - load S-Record file over serial line\n",
1127     "[ off ]\n"
1128     "    - load S-Record file over serial line with offset 'off'\n"
1129 );
1130 #endif  /* CFG_LOADS_BAUD_CHANGE */
1131 
1132 /*
1133  * SAVES always requires LOADS support, but not vice versa
1134  */
1135 
1136 
1137 #if (CONFIG_COMMANDS & CFG_CMD_SAVES)
1138 #ifdef  CFG_LOADS_BAUD_CHANGE
1139 U_BOOT_CMD(
1140     saves, 4, 0,    do_save_serial,
1141     "saves   - save S-Record file over serial line\n",
1142     "[ off ] [size] [ baud ]\n"
1143     "    - save S-Record file over serial line"
1144     " with offset 'off', size 'size' and baudrate 'baud'\n"
1145 );
1146 #else   /* ! CFG_LOADS_BAUD_CHANGE */
1147 U_BOOT_CMD(
1148     saves, 3, 0,    do_save_serial,
1149     "saves   - save S-Record file over serial line\n",
1150     "[ off ] [size]\n"
1151     "    - save S-Record file over serial line with offset 'off' and size 'size'\n"
1152 );
1153 #endif  /* CFG_LOADS_BAUD_CHANGE */
1154 #endif  /* CFG_CMD_SAVES */
1155 #endif  /* CFG_CMD_LOADS */
1156 
1157 
1158 #if (CONFIG_COMMANDS & CFG_CMD_LOADB)
1159 U_BOOT_CMD(
1160     loadb, 3, 0,    do_load_serial_bin,
1161     "loadb   - load binary file over serial line (kermit mode)\n",
1162     "[ off ] [ baud ]\n"
1163     "    - load binary file over serial line"
1164     " with offset 'off' and baudrate 'baud'\n"
1165 );
1166 
1167 /* support xmodem, www.arm9.net */
1168 U_BOOT_CMD(
1169     loadx, 3, 0,    do_load_serial_bin,
1170     "loadx   - load binary file over serial line (xmodem mode)\n",
1171     "[ off ] [ baud ]\n"
1172     "    - load binary file over serial line"
1173     " with offset 'off' and baudrate 'baud'\n"
1174 );
1175 
1176 U_BOOT_CMD(
1177     loady, 3, 0,    do_load_serial_bin,
1178     "loady   - load binary file over serial line (ymodem mode)\n",
1179     "[ off ] [ baud ]\n"
1180     "    - load binary file over serial line"
1181     " with offset 'off' and baudrate 'baud'\n"
1182 );
1183 
1184 #endif  /* CFG_CMD_LOADB */
1185 
1186 /* -------------------------------------------------------------------- */
1187 
1188 #if (CONFIG_COMMANDS & CFG_CMD_HWFLOW)
1189 int do_hwflow (cmd_tbl_t *cmdtp, int flag, int argc, char *argv[])
1190 {
1191     extern int hwflow_onoff(int);
1192 
1193     if (argc == 2) {
1194         if (strcmp(argv[1], "off") == 0)
1195             hwflow_onoff(-1);
1196         else
1197             if (strcmp(argv[1], "on") == 0)
1198                 hwflow_onoff(1);
1199             else
1200                 printf("Usage: %s\n", cmdtp->usage);
1201     }
1202     printf("RTS/CTS hardware flow control: %s\n", hwflow_onoff(0) ? "on" : "off");
1203     return 0;
1204 }
1205 
1206 /* -------------------------------------------------------------------- */
1207 
1208 U_BOOT_CMD(
1209     hwflow, 2, 0,   do_hwflow,
1210     "hwflow  - turn the harwdare flow control on/off\n",
1211     "[on|off]\n - change RTS/CTS hardware flow control over serial line\n"
1212 );
1213 
1214 #endif /* CFG_CMD_HWFLOW */
