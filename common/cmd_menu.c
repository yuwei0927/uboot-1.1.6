/*
 * mike.arm9@163.com, www.arm9.net
 *
 */

#include <common.h>
#include <command.h>
#include <def.h>
#include <nand.h>

#ifdef CONFIG_SURPORT_WINCE
#include "../wince/loader.h"
#endif

extern char console_buffer[];
extern int readline (const char *const prompt);
extern char awaitkey(unsigned long delay, int* error_p);
extern void download_nkbin_to_flash(void);

/**
 * Parses a string into a number.  The number stored at ptr is
 * potentially suffixed with K (for kilobytes, or 1024 bytes),
 * M (for megabytes, or 1048576 bytes), or G (for gigabytes, or
 * 1073741824).  If the number is suffixed with K, M, or G, then
 * the return value is the number multiplied by one kilobyte, one
 * megabyte, or one gigabyte, respectively.
 *
 * @param ptr where parse begins
 * @param retptr output pointer to next char after parse completes (output)
 * @return resulting unsigned int
 */
static unsigned long memsize_parse2 (const char *const ptr, const char **retptr)
{
	unsigned long ret = simple_strtoul(ptr, (char **)retptr, 0);
    int sixteen = 1;

	switch (**retptr) {
		case 'G':
		case 'g':
			ret <<= 10;
		case 'M':
		case 'm':
			ret <<= 10;
		case 'K':
		case 'k':
			ret <<= 10;
			(*retptr)++;
            sixteen = 0;
		default:
			break;
	}

    if (sixteen)
        return simple_strtoul(ptr, NULL, 16);
    
	return ret;
}


void param_menu_usage()
{
    printf("\r\n##### Parameter Menu #####\r\n");
    printf("[v] View the parameters\r\n");
    printf("[s] Set parameter \r\n");
    printf("[d] Delete parameter \r\n");
    printf("[w] Write the parameters to flash memeory \r\n");
    printf("[q] Quit \r\n");
    printf("Enter your selection: ");
}


void param_menu_shell(void)
{
    char c;
    char cmd_buf[256];
    char name_buf[20];
    char val_buf[256];
    
    while (1)
    {
        param_menu_usage();
        c = awaitkey(-1, NULL);
        printf("%c\n", c);
        switch (c)
        {
            case 'v':
            {
                strcpy(cmd_buf, "printenv ");
                printf("Name(enter to view all paramters): ");
                readline(NULL);
                strcat(cmd_buf, console_buffer);
                run_command(cmd_buf, 0);
                break;
            }
            
            case 's':
            {
                sprintf(cmd_buf, "setenv ");

                printf("Name: ");
                readline(NULL);
                strcat(cmd_buf, console_buffer);

                printf("Value: ");
                readline(NULL);
                strcat(cmd_buf, " ");
                strcat(cmd_buf, console_buffer);

                run_command(cmd_buf, 0);
                break;
            }
            
            case 'd':
            {
                sprintf(cmd_buf, "setenv ");

                printf("Name: ");
                readline(NULL);
                strcat(cmd_buf, console_buffer);

                run_command(cmd_buf, 0);
                break;
            }
            
            case 'w':
            {
                sprintf(cmd_buf, "saveenv");
                run_command(cmd_buf, 0);
                break;
            }
            
            case 'q':
            {
                return;
                break;
            }
        }
    }
}


void main_menu_usage(void)
{
    printf("\r\n##### open24x0 Bootloader for FA24x0 #####\r\n");

    printf("[u] Download u-boot\r\n");
#ifdef CONFIG_SURPORT_WINCE
	printf("[e] Download Eboot\r\n");
#endif
    printf("[k] Download Linux kernel\r\n");
#ifdef CONFIG_SURPORT_WINCE
    printf("[w] Download WinCE NK.bin\r\n");
#endif
    printf("[j] Download JFFS2 image\r\n");
    printf("[y] Download YAFFS image\r\n");
    printf("[d] Download to SDRAM & Run\r\n");
    printf("[b] Boot the system\r\n");
    printf("[f] Format the Nand Flash\r\n");
    printf("[s] Set the boot parameters\r\n");
    printf("[r] Reboot u-boot\r\n");
    printf("[q] Quit from menu\r\n");
    printf("Enter your selection: ");
}


void menu_shell(void)
{
    char c;
    char cmd_buf[200];
    char *p = NULL;
    unsigned long size;
    unsigned long offset;
    struct mtd_info *mtd = &nand_info[nand_curr_device];

    while (1)
    {
        main_menu_usage();
        c = awaitkey(-1, NULL);
        printf("%c\n", c);
        switch (c)
        {
            case 'u':
            {
                if (bBootFrmNORFlash())
                {
                    strcpy(cmd_buf, "usbslave 1 0x30000000; protect off all; erase 0 +$(filesize); cp.b 0x30000000 0 $(filesize)");
                }
                else
                {
                    strcpy(cmd_buf, "usbslave 1 0x30000000; nand erase bios; nand write.jffs2 0x30000000 bios $(filesize)");
                }
                run_command(cmd_buf, 0);
                break;
            }
            
#ifdef CONFIG_SURPORT_WINCE
            case 'e':
            {
                offset = EBOOT_BLOCK * mtd->erasesize;
                size   = EBOOT_BLOCK_SIZE * mtd->erasesize;
                sprintf(cmd_buf, "nand erase 0x%x 0x%x; usbslave 1 0x30000000; nand write 0x30000000 0x%x $(filesize)", offset, size, offset);
                run_command(cmd_buf, 0);
                break;
            }
#endif

            case 'k':
            {
                strcpy(cmd_buf, "usbslave 1 0x30000000; nand erase kernel; nand write.jffs2 0x30000000 kernel $(filesize)");
                run_command(cmd_buf, 0);
#ifdef CONFIG_SURPORT_WINCE
                if (!TOC_Read())
                    TOC_Erase();                
#endif                
                break;
            }

#ifdef CONFIG_SURPORT_WINCE
            case 'w':
            {
                download_nkbin_to_flash();
                break;
            }
#endif

            case 'j':
            {
                strcpy(cmd_buf, "usbslave 1 0x30000000; nand erase jffs2; nand write.jffs2 0x30000000 jffs2 $(filesize)");
                run_command(cmd_buf, 0);
                break;
            }

            case 'y':
            {
                strcpy(cmd_buf, "usbslave 1 0x30000000; nand erase yaffs; nand write.yaffs 0x30000000 yaffs $(filesize)");
                run_command(cmd_buf, 0);
                break;
            }

            case 'd':
            {
                extern volatile U32 downloadAddress;
                extern int download_run;
                
                download_run = 1;
                strcpy(cmd_buf, "usbslave 1");
                run_command(cmd_buf, 0);
                download_run = 0;
                sprintf(cmd_buf, "go %x", downloadAddress);
                run_command(cmd_buf, 0);
                break;
            }

            case 'b':
            {
#ifdef CONFIG_SURPORT_WINCE
                if (!TOC_Read())
                {
                    /* Launch wince */
                    printf("Booting wince ...\n");
                    strcpy(cmd_buf, "wince");
                    run_command(cmd_buf, 0);
                }
                else
#endif
                {
                    printf("Booting Linux ...\n");
                    strcpy(cmd_buf, "nand read.jffs2 0x32000000 kernel; bootm 0x32000000");
                    run_command(cmd_buf, 0);
                }
                break;
            }

            case 'f':
            {
                strcpy(cmd_buf, "nand erase ");

                printf("Start address: ");
                readline(NULL);
                strcat(cmd_buf, console_buffer);

                printf("Size(eg. 4000000, 0x4000000, 64m and so on): ");
                readline(NULL);
                p = console_buffer;
                size = memsize_parse2(p, &p);
                sprintf(console_buffer, " %x", size);
                strcat(cmd_buf, console_buffer);

                run_command(cmd_buf, 0);
                break;
            }

            case 's':
            {
                param_menu_shell();
                break;
            }

            case 'r':
            {
				strcpy(cmd_buf, "reset");
				run_command(cmd_buf, 0);
                break;
            }
            
            case 'q':
            {
                return;    
                break;
            }

        }
                
    }
}

int do_menu (cmd_tbl_t *cmdtp, int flag, int argc, char *argv[])
{
    menu_shell();
    return 0;
}

U_BOOT_CMD(
	menu,	3,	0,	do_menu,
	"menu - display a menu, to select the items to do something\n",
	" - display a menu, to select the items to do something"
);

