/*
 * Arduino Bank Vault Shell
 *     -- a game to hack a bank vault computer system and open the vault
 * Author: Thomas Cannon
 * Website: http://thomascannon.net
 * Date: 2010-10-03
 *
 * Licenced under a Creative Commons Attribution-ShareAlike Licence. 
 * Please read the license for full details:
 *     http://creativecommons.org/licenses/by-sa/3.0/
 *
 * Using code from Arduino UART Shell by Jiashu Lin
 *
 */

#include <avr/pgmspace.h>
#include "pitches.h"

/* Macro define */

/* Vault command buffer size */
#define VAULT_BUF_SIZE   32

/* Vault command max length */
#define VAULT_CMD_LENGH_MAX (VAULT_BUF_SIZE - 1)

/* Vault command max parameter count */
#define VAULT_PARA_CNT_MAX 2

/* type defines */
/* Vault command function prototype */
typedef int (*vault_cmd_func)(char * args[], char num_args);

/* Vault command structure */
typedef struct vault_cmd_struct
{
  char *name;
  char *help;
  int level; //the admin level required to execute the command
  vault_cmd_func do_cmd;
} vault_cmd_struct_t;

/* Vault command set array, additional commands may be added here */
const vault_cmd_struct_t vault_cmd_set[] =
{
    {"help", "\tthis help screen", 1, vault_cmd_help},
    {"list", "\tdisplay a list of files on the system", 1, vault_cmd_list},
    {"show", "\tshow the contents of a file. Usage: show [filename]", 1, vault_cmd_show},    
    {"del", "\tdelete a file. Usage: del [filename]", 2, vault_cmd_del},
    {"admin", "\tre-authenticate as admin", 1, vault_cmd_admin},   
    {"debug", "\trun debug tools", 1, vault_cmd_debug},           
    {"unlock", "\tunlock vault. Usage: unlock [4 digit pin]", 4, vault_cmd_unlock},    

    {0,0,0,0}
};

/* Vault command buffer */
static unsigned char vault_buf[VAULT_BUF_SIZE];
/* Vault command buffer write pointer */
static unsigned char vault_wptr = 0;
/* Vault command parameter pointer */
static char * vault_para_ptr[VAULT_PARA_CNT_MAX];

/* Vault cfgfile boolean */
static unsigned char vault_cfgfile = 1;
/* Admin level */
int vault_level = 0;
/* If in password mode then mask input */
static unsigned char password_mode = 0;

int ledPin1 =  13;    // Green LED connected to digital pin 13
int ledPin2 =  12;    // Yellow LED connected to digital pin 12
int speakerPin =  9;    // Speaker connected to digital pin 9
int lockPin =  10;    // Solenoid connected to digital pin 10

/* Vault password list */
const char* vault_passwd_list[] =
{
  "password",  //level 1
  "ducky",    //level 2
  "limbo",     //level 3
  "superbad9"     //level 4!!
};

int melody[] = {NOTE_C4, NOTE_G3,NOTE_G3, NOTE_A3, NOTE_G3,0, NOTE_B3, NOTE_C4};
int noteDurations[] = {4, 8, 8, 4,4,4,4,4 };

// Thanks to JEREMY E. BLUM for the following notes used in his project:  
int melody_fail[] = {NOTE_D4,NOTE_D3,NOTE_D2,NOTE_D1};
int noteDurations_fail[] = {4,4,4,1};

/* Function to read and print strings stored in flash so we can save RAM */
void vault_print(const prog_char str[]) 
{ 
  char c;
  if(!str) return;
  while((c = pgm_read_byte(str++)))
    Serial.print(c,BYTE);
} 

/* flush the UART command buffer */
void uart_cmd_svr_flush_buf(void)
{
    vault_wptr = 0;
    memset(vault_buf,0,sizeof(vault_buf));
    memset(vault_para_ptr,0,sizeof(vault_para_ptr));
}

/* init the UART command server, should call in setup() */
void uart_cmd_svr_init(void)
{
    Serial.begin(9600);
    Serial.flush();
    uart_cmd_svr_flush_buf();
    vault_print(PSTR("\r   ---Welcome to Acme Bank Secure Vault---\r\n"));
    uart_cmd_prompt();
}

/* Execute the command in the command buffer */
void uart_cmd_execute(void)
{
    unsigned char i = 0, para_cnt = 0, err = 0;

    while((para_cnt < VAULT_PARA_CNT_MAX) && \
	    (vault_para_ptr[para_cnt]) && \
	    (*vault_para_ptr[para_cnt]))
    {
	  para_cnt++;
    }

    if(password_mode)
    {
      password_mode = 0;
      err = vault_cmd_authenticate((char*)vault_buf);
    }
    else{
    while(0 != (vault_cmd_set[i].name))
    {
	  if(!strcmp((char*)vault_buf,vault_cmd_set[i].name))
	  {
	    if(vault_level >= vault_cmd_set[i].level)
            {
              Serial.println();
	      err = vault_cmd_set[i].do_cmd(vault_para_ptr, para_cnt);
	      //Serial.println("\r\n");
	      //uart_cmd_svr_flush_buf();
	      //uart_cmd_prompt();
            }
            else
            {
              vault_print(PSTR("\r\nError: You do not have sufficient privileges to execute that command.\r\n"));
            }
	     break;
	  }
	  i++;
    }
    }
    
    if(err) Serial.println("\r\nError:");
    uart_cmd_svr_flush_buf();
    if(!password_mode) uart_cmd_prompt();
}

/* print the command shell prompt */
void uart_cmd_prompt()
{
  if(vault_level<1) {
    vault_cmd_admin(0,0);
  }
  else
  {
    Serial.print("\r\n");
    vault_print(PSTR("admin@vault("));
    Serial.print(vault_level);
    vault_print(PSTR("): "));
  }
}

/* uart command server service routine, should call in loop() */
void uart_cmd_service()
{
    char c = 0;
    char i = 0;
    while(Serial.available())
    {
	// read one byte from serial port
	c = Serial.read();

	// if the first byte is ' ' or '\n', ignore it
	if((0 == vault_wptr)&&('\r' == c))
	{
          password_mode = 0;
	  uart_cmd_prompt();
	  continue;
	}

	// if '\n' is read, execute the command
	if('\r' == c)
	{
	  uart_cmd_execute();
	}
	// if ' ' is read, record the parameter ptr
	else if(' ' == c && !password_mode)
	{
	  // damping the space
	  if(vault_buf[vault_wptr-1])
	  {
		// replace it with NULL
		vault_buf[vault_wptr] = 0;

		vault_wptr++;

		// record the parameter address
		for(i = 0; i < VAULT_PARA_CNT_MAX; i++)
		{
		    if(!vault_para_ptr[i])
		    {
			vault_para_ptr[i] = (char*)(&vault_buf[vault_wptr]);
                        Serial.print(" "); //echo
			break;
		    }
		}

		if(VAULT_PARA_CNT_MAX == i)
		{
		    uart_cmd_execute();
		    break;
		}
	  }
	}
	// other characters, just record it
	else
	{
	    vault_buf[vault_wptr] = c;
	    vault_wptr++;
            if(password_mode)
            {
              Serial.print("*"); //echo
            }
            else
            {
              Serial.print(c); //echo
            }
	    if(vault_wptr == VAULT_CMD_LENGH_MAX)
	    {
		uart_cmd_execute();
	    }
	}
    }
}

/* play success melody */
void play_success()
{
  // iterate over the notes of the melody:
  for (int thisNote = 0; thisNote < 8; thisNote++) {

    // to calculate the note duration, take one second 
    // divided by the note type.
    //e.g. quarter note = 1000 / 4, eighth note = 1000/8, etc.
    int noteDuration = 1000/noteDurations[thisNote];
    tone(speakerPin, melody[thisNote],noteDuration);

    // to distinguish the notes, set a minimum time between them.
    // the note's duration + 30% seems to work well:
    int pauseBetweenNotes = noteDuration * 1.30;
    delay(pauseBetweenNotes);
  }
}

/* play fail melody */
void play_fail()
{
  for (int thisNote = 0; thisNote < 8; thisNote++) {
    int noteDuration = 1000/noteDurations_fail[thisNote];
    tone(speakerPin, melody_fail[thisNote],noteDuration);
    int pauseBetweenNotes = noteDuration * 1.30;
    delay(pauseBetweenNotes);
  }
}

/* help command implementation */
int vault_cmd_help(char * args[], char num_args)
{
    char i = 0;

  vault_print(PSTR("\r\nAcme Secure Vault v1.00 \r\nCommand list:\r\n"));

    while (vault_cmd_set[i].name)
    {
	 Serial.print(vault_cmd_set[i].name);
	 Serial.print("\t");
	 Serial.println(vault_cmd_set[i].help);
	 i++;
    }

    return 0;
}

/* list command implementation */
int vault_cmd_list(char * args[], char num_args)
{
  vault_print(PSTR("filename       size    date        time   owner\r\n"));
  vault_print(PSTR("------------------------------------------------\r\n"));
  vault_print(PSTR("readme.txt      110    2010-01-29  20:59  simon\r\n"));
  vault_print(PSTR("passwd.txt      408    2010-01-29  20:59  admin\r\n"));
  if(vault_cfgfile)
  {
  vault_print(PSTR("debug.cfg        22    2010-01-29  20:59  system\r\n"));
  }
    return 0;
}

/* show command implementation */
int vault_cmd_show(char * args[], char num_args)
{
  if(0 == strcmp(args[0],"passwd.txt"))
  {
     if(vault_level > 1)
     {
    vault_print(PSTR("#Vault system password file\r\n")); 
    vault_print(PSTR("#admin level : encrypted password\r\n")); 
    vault_print(PSTR("\r\n")); 
    vault_print(PSTR("1: cnffjbeq\r\n")); 
    vault_print(PSTR("2: qhpxl\r\n")); 
    vault_print(PSTR("3: yvzob\r\n")); 
     }
     else
  {
    vault_print(PSTR("Error: You need to be admin level 2 to show this file\r\n")); 
  }
  }
  else if(0 == strcmp(args[0],"readme.txt"))
  {
    vault_print(PSTR("John, just finished setting up the vault system.\r\n")); 
    vault_print(PSTR("If you need level 2 admin just run the admin command\r\n")); 
    vault_print(PSTR("and type \"ducky\" when prompted for a password.\r\n")); 
    vault_print(PSTR("Thanks, Simon\r\n"));  
  }
  else if(0 == strcmp(args[0],"debug.cfg") && vault_cfgfile)
  {
    vault_print(PSTR("#Configuration file for debug tools\r\n")); 
    vault_print(PSTR("allowed_user = system;\r\n")); 
  }
  else
  {
    vault_print(PSTR("Error: File not found\r\n")); 
  }
    return 0;
}

/* delete command implementation */
int vault_cmd_del(char * args[], char num_args)
{
    if(0 == strcmp(args[0],"debug.cfg") && vault_cfgfile)
  {
    if(vault_level > 2)
    {
    vault_cfgfile=0;
    vault_print(PSTR("Deleted debug.cfg\r\n")); 
    }
    else
    {
      vault_print(PSTR("Error: You do not have sufficient privileges to delete this file\r\n"));
    }
  }
  else if(0 == strcmp(args[0],"passwd.txt") || 0 == strcmp(args[0],"readme.txt"))
  {
    vault_print(PSTR("Error: You do not have sufficient privileges to delete this file\r\n")); 
  }
  else
  {
    vault_print(PSTR("Error: File not found\r\n")); 
  }
    return 0;
}

/* debug command implementation */
int vault_cmd_debug(char * args[], char num_args)
{
    if(vault_cfgfile)
  {
    vault_print(PSTR("Error. Debug tools can only be run by the following user: system\r\n")); 
  }
  else
  {
    vault_print(PSTR("Error: process closed unexpectedly. Memory dump:\r\n")); 
    vault_print(PSTR("KJHKF*£&$~F@FG{:>|\\.!!FJKFHSH00292\r\n")); 
    vault_print(PSTR("$&&(£$K;;[level4][superbad9]*$@#~}\r\n")); 
  }
    return 0;
}

/* unlock command implementation */
int vault_cmd_unlock(char * args[], char num_args)
{
    if(0 == strcmp(args[0],"5678"))
  {
    vault_print(PSTR("Vault unlocked...\r\n")); 
    digitalWrite(lockPin, HIGH);  
    digitalWrite(ledPin1, HIGH);
    digitalWrite(ledPin2, LOW);  
    play_success();
    delay(5000);                 
    digitalWrite(lockPin, LOW);  
    digitalWrite(ledPin1, LOW);
    digitalWrite(ledPin2, HIGH); 
  }
  else
  {
    vault_print(PSTR("Error: incorrect pin\r\n")); 
  }
    return 0;
}

/* admin command implementation */
int vault_cmd_admin(char * args[], char num_args)
{
    password_mode=1;
    vault_print(PSTR("\r\nEnter admin password: "));

    return 0;
}

/* admin authenticate implementation */
int vault_cmd_authenticate(char * password)
{
  unsigned char i = 0;
  
  vault_print(PSTR("\r\nVerifying..."));
  delay(500);
  
      
  while(0 != (vault_passwd_list[i]))
    {
	  if(!strcmp(password,vault_passwd_list[i]))
	  {
            vault_level = i+1;
            vault_print(PSTR("password accepted\r\nYou are a level "));
            Serial.print(vault_level);
            vault_print(PSTR(" admin\r\n"));
	    return 0;
	  }
	  i++;
    }
    vault_print(PSTR("password invalid\r\n"));
    play_fail();
    return 0;
}

void setup()
{
  pinMode(lockPin, OUTPUT);     
  pinMode(ledPin1, OUTPUT);
  pinMode(ledPin2, OUTPUT);
  pinMode(speakerPin, OUTPUT); 
  digitalWrite(ledPin2, HIGH);
  /* initiate the uart command server */
  uart_cmd_svr_init();
}

void loop()
{
  /* service the uart command */
  uart_cmd_service();
}
 
