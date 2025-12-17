import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.enableCors({
    origin: ['https://v0.app/chat/coworking-seat-management-iPcZe687hoG',
      'https://v0.app/chat/coworking-seat-management-iPcZe687hoG#MvsH4roXDikWSXTOMb9HKbhoAxLiuXKu',
      'https://v0.app/',
    ],

    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  });


    const config = new DocumentBuilder()
    .setTitle('Your API Title')
    .setDescription('The API description')
    .setVersion('1.0')
    .addTag('api-tag') // Optional: Adds a tag to group endpoints
    .build();
  
  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup('api', app, document); // 'api' is the endpoint where docs will be served
  await app.listen(process.env.PORT ?? 3000);
}
bootstrap();
