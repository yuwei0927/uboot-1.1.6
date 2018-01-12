/*
 * (C) Copyright 2002
 * Sysgo Real-Time Solutions, GmbH <www.elinos.com>
 * Marius Groeger <mgroeger@sysgo.de>
 *
 * (C) Copyright 2002
 * David Mueller, ELSOFT AG, <d.mueller@elsoft.ch>
 *
 * See file CREDITS for list of people who contributed to this
 * project.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston,
 * MA 02111-1307 USA
 */

#include <common.h>
#include <s3c2410.h>

DECLARE_GLOBAL_DATA_PTR;

/*
 * Miscellaneous platform dependent initialisations
 */

int board_init (void)
{
//    S3C24X0_CLOCK_POWER * const clk_power = S3C24X0_GetBase_CLOCK_POWER();
    S3C24X0_GPIO * const gpio = S3C24X0_GetBase_GPIO();

    /* set up the I/O ports */
    gpio->GPACON = 0x007FFFFF;
    gpio->GPBCON = 0x00044555;
    gpio->GPBUP = 0x000007FF;
    gpio->GPCCON = 0xAAAAAAAA;
    gpio->GPCUP = 0x0000FFFF;
    gpio->GPDCON = 0xAAAAAAAA;
    gpio->GPDUP = 0x0000FFFF;
    gpio->GPECON = 0xAAAAAAAA;
    gpio->GPEUP = 0x0000FFFF;
    gpio->GPFCON = 0x000055AA;
    gpio->GPFUP = 0x000000FF;
    gpio->GPGCON = 0xFF95FFBA;
    gpio->GPGUP = 0x0000FFFF;
    gpio->GPHCON = 0x002AFAAA;
    gpio->GPHUP = 0x000007FF;

    /* support both of S3C2410 and S3C2440, by www.arm9.net */
    if ((gpio->GSTATUS1 == 0x32410000) || (gpio->GSTATUS1 == 0x32410002))
    {
        /* arch number of SMDK2410-Board */
        gd->bd->bi_arch_number = MACH_TYPE_SMDK2410;
    }
    else if (gpio->GSTATUS1 == 0x32440001)   //S3C2440 chip
    {
        /* arch number of SMDK2440-Board */
        gd->bd->bi_arch_number = MACH_TYPE_S3C2440;
    }

    /* adress of boot parameters */
    gd->bd->bi_boot_params = 0x30000100;
    icache_enable();
#if 0
    dcache_enable();
#endif
    return 0;
}

int dram_init (void)
{
	int i;
	for (i=0;i<CONFIG_NR_DRAM_BANKS;i++){
	    gd->bd->bi_dram[i].start = PHYS_SDRAM_1;
    	gd->bd->bi_dram[i].size = PHYS_SDRAM_1_SIZE;
	}

    return 0;
}

#ifdef CONFIG_SPEAKER
int	audio_init(void)
{
	S3C24X0_GPIO * const gpio = S3C24X0_GetBase_GPIO();
	S3C24X0_TIMERS * const timers = S3C24X0_GetBase_TIMERS();
	unsigned int freq = 5000;

	/* set GPB0 as TOUT0 */  
	gpio->GPBCON = (gpio->GPBCON & ~0x3) | 0x2;

	timers->TCFG0 = (timers->TCFG0 & ~0xff) | 15;
	timers->TCFG1 &= ~0xF;
	timers->TCFG1 != 2;
	timers->ch[0].TCNTB = freq;
	timers->ch[0].TCMPB = freq/2;
	timers->TCON &= ~0x1f;
	timers->TCON |= 0xb;
	timers->TCON &= ~0x2;

	return 0;
}
#endif  /* CONFIG_SPEAKER */

#if defined(CONFIG_DISPLAY_CPUINFO)
int print_cpuinfo (void)
{
	S3C24X0_GPIO * const gpio = S3C24X0_GetBase_GPIO();
	S3C24X0_CLOCK_POWER * const clk_power = S3C24X0_GetBase_CLOCK_POWER();

	unsigned int mpll_val, upll_val;
	
	printf ("Chip ID:0x%x\n", gpio->GSTATUS1);
	
	if ((gpio->GSTATUS1 == 0x32410000) || (gpio->GSTATUS1 == 0x32410002)){
        puts ("This CPU chip is S3C2410\n");
    }else if (gpio->GSTATUS1 == 0x32440001) {
        puts ("This CPU chip is S3C2440\n");
    }else{
		puts ("Unkown CPU chip!\n");
		return -1;
	}

	mpll_val = clk_power->MPLLCON;
	upll_val = clk_power->UPLLCON; 

	//print the Clock info
	puts ("+---------------------------------------------+\n");
	printf ("HCLK = %ldMHz\n", get_HCLK()/1000/1000);
	printf ("PCLK = %ldMHz\n", get_PCLK()/1000/1000);
	printf ("UCLK = %ldMHz\n", get_UCLK()/1000/1000);
	printf ("FCLK = %ldMHz\n", get_FCLK()/1000/1000);
	printf("UPLLVal [M:%xh,P:%xh,S:%xh]\n", (upll_val&(0xff<<12))>>12,(upll_val&(0x3f<<4))>>4,(upll_val&0x3));
	printf("MPLLVal [M:%xh,P:%xh,S:%xh]\n", (mpll_val&(0xff<<12))>>12,(mpll_val&(0x3f<<4))>>4,(mpll_val&0x3));
	printf("CLKDIVN: %xh\n", clk_power->CLKDIVN);
	puts ("+---------------------------------------------+\n");
	
	return 0;

}
#endif

#if defined(CONFIG_DISPLAY_BOARDINFO)
int checkboard(void)
{
	printf("Board: %s\n", BOARD_NAME);
	return 0;
}
#endif


